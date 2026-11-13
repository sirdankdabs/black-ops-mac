/* GLib 2.80 headers call g_once_init_{enter,leave}_pointer from G_DEFINE_TYPE;
 * the GStreamer runtime the engine ships has GLib 2.78, which only has the
 * generic g_once_init_{enter,leave}. Linked into winegstreamer.so. */
typedef unsigned long gsize;
extern int g_once_init_enter(volatile void *location);
extern void g_once_init_leave(volatile void *location, gsize result);
__attribute__((visibility("hidden"))) int g_once_init_enter_pointer(void *location)
{ return g_once_init_enter(location); }
__attribute__((visibility("hidden"))) void g_once_init_leave_pointer(void *location, void *result)
{ g_once_init_leave(location, (gsize)result); }
