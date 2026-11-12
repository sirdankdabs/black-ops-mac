/*
 * mvkcache: a persistent, parallel pipeline cache for MoltenVK.
 *
 * DXVK 1.10 creates its pipelines without a VkPipelineCache, so every run
 * translates each shader again (SPIR-V -> MSL with SPIRV-Cross, x86_64 code
 * under Rosetta: ~7 ms a shader, two per pipeline, thousands per map).
 *
 * This library is installed as libMoltenVK.dylib (the real one is renamed
 * libMoltenVK.real.dylib and re-exported), so every Wine process uses it.
 * It gives each device a set of pipeline caches, filled with what was saved
 * last time, and writes them back to disk once pipeline creation has been
 * quiet for a few seconds (and at least every 60 s while it goes on),
 * only the caches that got new pipelines.
 *
 * Why several caches: MoltenVK holds a pipeline cache's lock while it
 * converts and compiles a shader for it, so with one shared cache every
 * compiler thread waits for the others (one Metal compile at a time; Black
 * Ops' first shader warming took minutes). Each pipeline goes to the cache
 * picked by a hash of its shaders' code, so the same shaders always meet
 * their saved translations, and different ones compile side by side.
 *
 *   MVKCACHE_FILE    cache file prefix (default: MVKCACHE_DEFAULT_FILE from
 *                    the build, else mvkcache.bin next to this library);
 *                    the caches are <prefix>.0 ... <prefix>.N-1
 *   MVKCACHE_SHARDS  number of caches, 1-32 (default 8)
 *   MVKCACHE_LOG     1: log to stderr
 *   MVKCACHE_OFF     1: pass through only
 *   MVKCACHE_FPS     1: log frame-time statistics every 5 s (stderr)
 */
#include <dlfcn.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef int32_t VkResult;
typedef void *VkInstance;
typedef void *VkDevice;
typedef uint64_t VkPipelineCache;
typedef uint64_t VkShaderModule;
typedef void (*PFN_vkVoidFunction)(void);
typedef struct {
    int32_t sType;
    const void *pNext;
    uint32_t flags;
    size_t initialDataSize;
    const void *pInitialData;
} VkPipelineCacheCreateInfo;
typedef struct {
    int32_t sType;
    const void *pNext;
    uint32_t flags;
    size_t codeSize;
    const uint32_t *pCode;
} VkShaderModuleCreateInfo;
typedef struct {
    int32_t sType;
    const void *pNext;
    uint32_t flags;
    uint32_t stage;
    VkShaderModule module;
    const char *pName;
    const void *pSpecializationInfo;
} VkPipelineShaderStageCreateInfo;
typedef struct {            /* leading members of VkGraphicsPipelineCreateInfo */
    int32_t sType;
    const void *pNext;
    uint32_t flags;
    uint32_t stageCount;
    const VkPipelineShaderStageCreateInfo *pStages;
} GfxInfoHead;
typedef struct {            /* leading members of VkComputePipelineCreateInfo */
    int32_t sType;
    const void *pNext;
    uint32_t flags;
    VkPipelineShaderStageCreateInfo stage;
} CmpInfoHead;

typedef PFN_vkVoidFunction (*PFN_GIPA)(VkInstance, const char *);
typedef PFN_vkVoidFunction (*PFN_GDPA)(VkDevice, const char *);
typedef VkResult (*PFN_CreatePC)(VkDevice, const VkPipelineCacheCreateInfo *, const void *, VkPipelineCache *);
typedef void (*PFN_DestroyPC)(VkDevice, VkPipelineCache, const void *);
typedef VkResult (*PFN_GetPCData)(VkDevice, VkPipelineCache, size_t *, void *);
typedef VkResult (*PFN_CreatePipes)(VkDevice, VkPipelineCache, uint32_t, const void *, const void *, void *);
typedef VkResult (*PFN_CreateSM)(VkDevice, const VkShaderModuleCreateInfo *, const void *, VkShaderModule *);
typedef void (*PFN_DestroyDevice)(VkDevice, const void *);

static PFN_GIPA real_gipa;
static PFN_GDPA real_gdpa;
static PFN_CreatePC real_create_pc;
static PFN_DestroyPC real_destroy_pc;
static PFN_GetPCData real_get_pc_data;
static PFN_CreatePipes real_create_gfx, real_create_cmp;
static PFN_CreateSM real_create_sm;
static PFN_DestroyDevice real_destroy_dev;

#define MAX_SHARDS 32
#define MAX_DEVS 8
static char cache_path[1024];
static int nshards = 8;
static struct { void *data; size_t size, saved; } shard[MAX_SHARDS];
static volatile uint32_t shard_dirty[MAX_SHARDS];   /* pipelines created since its last save */
static int logging, disabled, fps_log;

/* each device's caches, one per shard */
static struct { VkDevice dev; VkPipelineCache pc[MAX_SHARDS]; } devs[MAX_DEVS];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;   /* devs[] and saving */
static volatile uint64_t created, last_create_ns, create_ns;
static uint64_t saved_count = (uint64_t)-1, last_save_ns;

#define LOG(...) do { if (logging) { fprintf(stderr, "[mvkcache] " __VA_ARGS__); fputc('\n', stderr); } } while (0)

static uint64_t now_ns(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }

/* ---- shader code hashes, by module handle ---- */

#define HASH_SLOTS (1 << 16)
static struct { VkShaderModule m; uint64_t h; } hashes[HASH_SLOTS];
static pthread_mutex_t hlock = PTHREAD_MUTEX_INITIALIZER;

static uint64_t fnv(const void *p, size_t n)
{
    const unsigned char *b = p;
    uint64_t h = 1469598103934665603ull;
    for (size_t i = 0; i < n; i++) { h ^= b[i]; h *= 1099511628211ull; }
    return h;
}

static size_t slot_of(VkShaderModule m) { return (size_t)((m * 0x9E3779B97F4A7C15ull) >> 48) & (HASH_SLOTS - 1); }

static void remember_hash(VkShaderModule m, uint64_t h)
{
    pthread_mutex_lock(&hlock);
    size_t s = slot_of(m);
    for (size_t i = 0; i < HASH_SLOTS; i++, s = (s + 1) & (HASH_SLOTS - 1))
        if (hashes[s].m == m || hashes[s].m == 0) { hashes[s].m = m; hashes[s].h = h; break; }
    pthread_mutex_unlock(&hlock);
}

static uint64_t module_hash(VkShaderModule m)
{
    uint64_t h = 0;
    pthread_mutex_lock(&hlock);
    size_t s = slot_of(m);
    for (size_t i = 0; i < HASH_SLOTS; i++, s = (s + 1) & (HASH_SLOTS - 1)) {
        if (hashes[s].m == m) { h = hashes[s].h; break; }
        if (hashes[s].m == 0) break;
    }
    pthread_mutex_unlock(&hlock);
    return h ? h : m;   /* unknown module: still spread, just not stable */
}

static VkResult my_create_sm(VkDevice dev, const VkShaderModuleCreateInfo *ci, const void *alloc, VkShaderModule *out)
{
    VkResult r = real_create_sm(dev, ci, alloc, out);
    if (r == 0 && ci && ci->pCode) remember_hash(*out, fnv(ci->pCode, ci->codeSize) | 1);
    return r;
}

/* ---- files ---- */

static void shard_file(int i, char *buf, size_t n) { snprintf(buf, n, "%s.%d", cache_path, i); }

static int read_file(const char *path, void **data, size_t *size)
{
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    void *p = n > 0 ? malloc(n) : NULL;
    int ok = p && fread(p, 1, n, f) == (size_t)n;
    fclose(f);
    if (!ok) { free(p); return 0; }
    *data = p; *size = n;
    return 1;
}

static void load_files(void)
{
    char path[1100];
    int found = 0;
    for (int i = 0; i < nshards; i++) {
        shard_file(i, path, sizeof path);
        if (read_file(path, &shard[i].data, &shard[i].size)) {
            shard[i].saved = shard[i].size;
            found++;
        }
    }
    LOG("loaded %d of %d caches from %s.*", found, nshards, cache_path);
}

/* Called with lock held. Writes a shard's cache if it outgrew its file. */
static void save_shard_locked(int i, VkDevice dev, VkPipelineCache pc)
{
    size_t size = 0;
    if (real_get_pc_data(dev, pc, &size, NULL) != 0 || size <= shard[i].saved) return;
    void *buf = malloc(size);
    if (!buf) return;
    if (real_get_pc_data(dev, pc, &size, buf) == 0 && size > shard[i].saved) {
        char path[1100], tmp[1200];
        shard_file(i, path, sizeof path);
        snprintf(tmp, sizeof tmp, "%s.%d.tmp", path, getpid());
        FILE *f = fopen(tmp, "wb");
        if (f && fwrite(buf, 1, size, f) == size && fclose(f) == 0 && rename(tmp, path) == 0) {
            LOG("saved cache %d: %zu bytes (%llu pipelines created)", i, size, (unsigned long long)created);
            shard[i].saved = size;
        } else {
            if (f) fclose(f);
            unlink(tmp);
        }
    }
    free(buf);
}

static void save_all_locked(void)
{
    for (int d = 0; d < MAX_DEVS; d++)
        if (devs[d].dev)
            for (int i = 0; i < nshards; i++)
                if (devs[d].pc[i] && __atomic_exchange_n(&shard_dirty[i], 0, __ATOMIC_ACQ_REL))
                    save_shard_locked(i, devs[d].dev, devs[d].pc[i]);
}

static void *saver(void *arg)
{
    (void)arg;
    /* Saving serializes and writes megabytes of cache: keep it on the
       efficiency cores at background priority, away from the game. */
    pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0);
    for (;;) {
        sleep(2);
        uint64_t c = created;
        /* Save once creation has paused for 10 s, so saving does not get in
           the way while the game is busy compiling; and at least every 120 s
           while it keeps compiling, so a game that is killed (Wine's
           processes usually are) does not lose what it compiled. */
        if (c == saved_count) continue;
        if (now_ns() - last_create_ns < 10000000000ull && now_ns() - last_save_ns < 120000000000ull) continue;
        LOG("%llu pipelines so far, %.2f ms each on average",
            (unsigned long long)c, c ? create_ns / 1e6 / c : 0.0);
        pthread_mutex_lock(&lock);
        save_all_locked();
        saved_count = c;
        last_save_ns = now_ns();
        pthread_mutex_unlock(&lock);
    }
    return NULL;
}

/* ---- the device's caches ---- */

static int resolve_cache_fns(VkDevice dev)
{
    if (!real_create_pc) real_create_pc = (PFN_CreatePC)real_gdpa(dev, "vkCreatePipelineCache");
    if (!real_destroy_pc) real_destroy_pc = (PFN_DestroyPC)real_gdpa(dev, "vkDestroyPipelineCache");
    if (!real_get_pc_data) real_get_pc_data = (PFN_GetPCData)real_gdpa(dev, "vkGetPipelineCacheData");
    return real_create_pc && real_destroy_pc && real_get_pc_data;
}

/* Creates the device's caches the first time; returns shard i's cache.
   Once a device's caches exist they are found without taking the lock, so
   pipeline creation never waits for a save. */
static volatile int devs_ready[MAX_DEVS];

static VkPipelineCache device_cache(VkDevice dev, int i)
{
    for (int d = 0; d < MAX_DEVS; d++)
        if (__atomic_load_n(&devs_ready[d], __ATOMIC_ACQUIRE) && devs[d].dev == dev) return devs[d].pc[i];
    pthread_mutex_lock(&lock);
    int d, free_slot = -1;
    for (d = 0; d < MAX_DEVS; d++) {
        if (devs[d].dev == dev) break;
        if (!devs[d].dev && free_slot < 0) free_slot = d;
    }
    if (d == MAX_DEVS) {
        if (free_slot < 0 || !resolve_cache_fns(dev)) { pthread_mutex_unlock(&lock); return 0; }
        d = free_slot;
        devs[d].dev = dev;
        int loaded = 0;
        for (int s = 0; s < nshards; s++) {
            VkPipelineCacheCreateInfo ci = { 17 /* VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO */, NULL, 0,
                                             shard[s].size, shard[s].data };
            VkResult r = shard[s].data ? real_create_pc(dev, &ci, NULL, &devs[d].pc[s]) : -1;
            if (r == 0) loaded++;
            else {
                ci.initialDataSize = 0; ci.pInitialData = NULL;
                if (real_create_pc(dev, &ci, NULL, &devs[d].pc[s]) != 0) devs[d].pc[s] = 0;
            }
        }
        LOG("device %p: %d caches, %d with saved data", dev, nshards, loaded);
        __atomic_store_n(&devs_ready[d], 1, __ATOMIC_RELEASE);
    }
    VkPipelineCache pc = devs[d].pc[i];
    pthread_mutex_unlock(&lock);
    return pc;
}

static void my_destroy_dev(VkDevice dev, const void *alloc)
{
    pthread_mutex_lock(&lock);
    for (int d = 0; d < MAX_DEVS; d++)
        if (devs[d].dev == dev) {
            __atomic_store_n(&devs_ready[d], 0, __ATOMIC_RELEASE);
            for (int i = 0; i < nshards; i++)
                if (devs[d].pc[i]) {
                    save_shard_locked(i, dev, devs[d].pc[i]);
                    real_destroy_pc(dev, devs[d].pc[i], NULL);
                    devs[d].pc[i] = 0;
                }
            devs[d].dev = NULL;
        }
    pthread_mutex_unlock(&lock);
    real_destroy_dev(dev, alloc);
}

static int shard_of(const VkPipelineShaderStageCreateInfo *st, uint32_t n)
{
    uint64_t h = 0;
    for (uint32_t i = 0; i < n; i++) h = h * 31 + module_hash(st[i].module);
    h ^= h >> 33; h *= 0xff51afd7ed558ccdull; h ^= h >> 33;
    return (int)(h % (uint64_t)nshards);
}

static VkResult my_create_gfx(VkDevice dev, VkPipelineCache pc, uint32_t n, const void *ci, const void *alloc, void *out)
{
    if (!pc && n) {
        const GfxInfoHead *g = ci;
        int s = shard_of(g->pStages, g->stageCount);
        pc = device_cache(dev, s);
        __atomic_store_n(&shard_dirty[s], 1, __ATOMIC_RELEASE);
    }
    uint64_t t = now_ns();
    VkResult r = real_create_gfx(dev, pc, n, ci, alloc, out);
    last_create_ns = now_ns();
    __atomic_add_fetch(&create_ns, last_create_ns - t, __ATOMIC_RELAXED);
    __atomic_add_fetch(&created, n, __ATOMIC_RELAXED);
    return r;
}

static VkResult my_create_cmp(VkDevice dev, VkPipelineCache pc, uint32_t n, const void *ci, const void *alloc, void *out)
{
    if (!pc && n) {
        const CmpInfoHead *c = ci;
        int s = shard_of(&c->stage, 1);
        pc = device_cache(dev, s);
        __atomic_store_n(&shard_dirty[s], 1, __ATOMIC_RELEASE);
    }
    VkResult r = real_create_cmp(dev, pc, n, ci, alloc, out);
    __atomic_add_fetch(&created, n, __ATOMIC_RELAXED);
    last_create_ns = now_ns();
    return r;
}

/* ---- frame-time statistics ---- */

typedef VkResult (*PFN_Present)(void *, const void *);
static PFN_Present real_present;
#define FT_MAX 4096
static float ft[FT_MAX];
static int ft_n;
static uint64_t ft_last, ft_start;

static int cmpf(const void *a, const void *b) { float x = *(const float *)a, y = *(const float *)b; return (x > y) - (x < y); }

static VkResult my_present(void *queue, const void *info)
{
    VkResult r = real_present(queue, info);
    uint64_t t = now_ns();
    if (ft_last && ft_n < FT_MAX) ft[ft_n++] = (t - ft_last) / 1e6f;
    ft_last = t;
    if (!ft_start) ft_start = t;
    if (t - ft_start >= 5000000000ull && ft_n > 10) {
        double sum = 0; int slow = 0;
        for (int i = 0; i < ft_n; i++) { sum += ft[i]; if (ft[i] > 1000.0f / 150) slow++; }
        qsort(ft, ft_n, sizeof *ft, cmpf);
        float p99 = ft[(int)(ft_n * 0.99)], p50 = ft[ft_n / 2], mx = ft[ft_n - 1];
        fprintf(stderr, "[fps] avg %.1f FPS, median %.2f ms, 1%% low %.1f FPS, worst %.1f ms, %d/%d frames over 6.7 ms\n",
                1000.0 * ft_n / sum, p50, 1000.0 / p99, mx, slow, ft_n);
        ft_n = 0; ft_start = t;
    }
    return r;
}

/* ---- entry points ---- */

static PFN_vkVoidFunction hook(const char *name, PFN_vkVoidFunction real)
{
    if (!real || disabled) return real;
#define H(n, var, fn) if (!strcmp(name, n)) { if (!var) var = (void *)real; return (PFN_vkVoidFunction)fn; }
    H("vkCreateShaderModule", real_create_sm, my_create_sm);
    H("vkCreateGraphicsPipelines", real_create_gfx, my_create_gfx);
    H("vkCreateComputePipelines", real_create_cmp, my_create_cmp);
    H("vkDestroyDevice", real_destroy_dev, my_destroy_dev);
    if (fps_log) { H("vkQueuePresentKHR", real_present, my_present); }
#undef H
    return real;
}

PFN_vkVoidFunction vkGetDeviceProcAddr(VkDevice dev, const char *name);

PFN_vkVoidFunction vkGetInstanceProcAddr(VkInstance inst, const char *name)
{
    if (!strcmp(name, "vkGetInstanceProcAddr")) return (PFN_vkVoidFunction)vkGetInstanceProcAddr;
    if (!strcmp(name, "vkGetDeviceProcAddr")) return (PFN_vkVoidFunction)vkGetDeviceProcAddr;
    return hook(name, real_gipa(inst, name));
}

PFN_vkVoidFunction vkGetDeviceProcAddr(VkDevice dev, const char *name)
{
    if (!strcmp(name, "vkGetDeviceProcAddr")) return (PFN_vkVoidFunction)vkGetDeviceProcAddr;
    return hook(name, real_gdpa(dev, name));
}

__attribute__((constructor)) static void init(void)
{
    Dl_info di;
    char dir[1024] = ".";
    if (dladdr((void *)init, &di) && di.dli_fname) {
        snprintf(dir, sizeof dir, "%s", di.dli_fname);
        char *s = strrchr(dir, '/');
        if (s) *s = 0;
    }
    logging = getenv("MVKCACHE_LOG") && atoi(getenv("MVKCACHE_LOG"));
    disabled = getenv("MVKCACHE_OFF") && atoi(getenv("MVKCACHE_OFF"));
    fps_log = getenv("MVKCACHE_FPS") && atoi(getenv("MVKCACHE_FPS"));
    if (getenv("MVKCACHE_SHARDS")) {
        int n = atoi(getenv("MVKCACHE_SHARDS"));
        if (n >= 1 && n <= MAX_SHARDS) nshards = n;
    }
    char mvk[1100];
    snprintf(mvk, sizeof mvk, "%s/libMoltenVK.real.dylib", dir);
    void *h = dlopen(mvk, RTLD_NOW | RTLD_LOCAL);
    if (!h) { fprintf(stderr, "[mvkcache] cannot load %s: %s\n", mvk, dlerror()); abort(); }
    real_gipa = (PFN_GIPA)dlsym(h, "vkGetInstanceProcAddr");
    real_gdpa = (PFN_GDPA)dlsym(h, "vkGetDeviceProcAddr");
    const char *p = getenv("MVKCACHE_FILE");
    if (p && *p) snprintf(cache_path, sizeof cache_path, "%s", p);
#ifdef MVKCACHE_DEFAULT_FILE
    else snprintf(cache_path, sizeof cache_path, "%s", MVKCACHE_DEFAULT_FILE);
#else
    else snprintf(cache_path, sizeof cache_path, "%s/mvkcache.bin", dir);
#endif
    if (disabled) return;
    load_files();
    pthread_t t;
    if (pthread_create(&t, NULL, saver, NULL) == 0) pthread_detach(t);
}
