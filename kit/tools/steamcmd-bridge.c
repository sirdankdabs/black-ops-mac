/* BO-Mac: steamcmd/steamcmd.sh for boiii's Workshop downloads.
 *
 * boiii takes Wine for Linux and starts ./steamcmd/steamcmd.sh, then waits
 * for it. Under Wine a Mac (Unix) program started from a Windows one has no
 * process handle, so boiii could not wait: it took every attempt for a quick
 * failure, started more SteamCMDs on the same files and reset the download.
 * This is a Windows program under that name, so boiii can wait for it; it
 * starts the Mac script next to it (bom-steamcmd.sh, Valve's macOS SteamCMD)
 * and waits for the "done.<token>" file that script writes with its exit
 * code. */
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

int wmain(int argc, WCHAR **argv)
{
    static WCHAR dir[MAX_PATH], cmd[32768], done[MAX_PATH];
    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    WCHAR *slash, *args = GetCommandLineW();
    DWORD token = GetCurrentProcessId() ^ GetTickCount();
    int quoted = 0, code = 1;
    FILE *f;

    GetModuleFileNameW(NULL, dir, MAX_PATH);
    if (!(slash = wcsrchr(dir, L'\\')) && !(slash = wcsrchr(dir, L'/'))) return 1;
    *slash = 0;
    /* our own arguments: the command line after the program name */
    while (*args && (quoted || (*args != L' ' && *args != L'\t'))) { if (*args == L'"') quoted = !quoted; args++; }
    swprintf(done, MAX_PATH, L"%ls\\done.%lu", dir, (unsigned long)token);
    DeleteFileW(done);
    swprintf(cmd, 32767, L"\"%ls\\bom-steamcmd.sh\" %lu%ls", dir, (unsigned long)token, args);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    if (!CreateProcessW(NULL, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) return 1;
    if (pi.hThread) CloseHandle(pi.hThread);
    if (pi.hProcess) CloseHandle(pi.hProcess);
    while (GetFileAttributesW(done) == INVALID_FILE_ATTRIBUTES) Sleep(500);
    Sleep(200);
    if ((f = _wfopen(done, L"r"))) { if (fscanf(f, "%d", &code) != 1) code = 1; fclose(f); }
    DeleteFileW(done);
    return code;
}
