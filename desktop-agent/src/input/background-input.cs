using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Collections.Generic;

class BackgroundInput
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Point
    {
        public int X;
        public int Y;
        public Point(int x, int y) { X = x; Y = y; }
    }

    [DllImport("user32.dll")]
    static extern IntPtr WindowFromPoint(Point point);

    [DllImport("user32.dll")]
    static extern bool ScreenToClient(IntPtr hWnd, ref Point lpPoint);

    [DllImport("user32.dll")]
    static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    const uint WM_MOUSEMOVE = 0x0200;
    const uint WM_LBUTTONDOWN = 0x0201;
    const uint WM_LBUTTONUP = 0x0202;
    const uint WM_RBUTTONDOWN = 0x0204;
    const uint WM_RBUTTONUP = 0x0205;
    const uint WM_MBUTTONDOWN = 0x0207;
    const uint WM_MBUTTONUP = 0x0208;
    const uint WM_LBUTTONDBLCLK = 0x0203;
    const uint WM_MOUSEWHEEL = 0x020A;

    const uint WM_KEYDOWN = 0x0100;
    const uint WM_KEYUP = 0x0101;
    const uint WM_CHAR = 0x0102;
    const uint WM_SYSKEYDOWN = 0x0104;
    const uint WM_SYSKEYUP = 0x0105;

    const int VK_CONTROL = 0x11;
    const int VK_MENU = 0x12; // Alt
    const int VK_SHIFT = 0x10;
    const int VK_LWIN = 0x5B;

    private static IntPtr lastTargetHWnd = IntPtr.Zero;

    private static Dictionary<string, int> VK_MAP = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
    {
        { "Enter", 0x0D },
        { "Return", 0x0D },
        { "Backspace", 0x08 },
        { "Tab", 0x09 },
        { "Escape", 0x1B },
        { "Space", 0x20 },
        { "Delete", 0x2E },
        { "ArrowUp", 0x26 },
        { "ArrowDown", 0x28 },
        { "ArrowLeft", 0x25 },
        { "ArrowRight", 0x27 },
        { "Home", 0x24 },
        { "End", 0x23 },
        { "PageUp", 0x21 },
        { "PageDown", 0x22 },
        { "Insert", 0x2D },
        { "F1", 0x70 }, { "F2", 0x71 }, { "F3", 0x72 }, { "F4", 0x73 },
        { "F5", 0x74 }, { "F6", 0x75 }, { "F7", 0x76 }, { "F8", 0x77 },
        { "F9", 0x78 }, { "F10", 0x79 }, { "F11", 0x7A }, { "F12", 0x7B }
    };

    static void Main(string[] args)
    {
        Console.WriteLine("BackgroundInput starting...");
        string line;
        while ((line = Console.ReadLine()) != null)
        {
            try
            {
                line = line.Trim();
                if (string.IsNullOrEmpty(line)) continue;

                string[] parts = line.Split(new char[] { ' ' }, 2);
                string cmd = parts[0].ToLower();
                string rest = parts.Length > 1 ? parts[1] : "";

                switch (cmd)
                {
                    case "click":
                        HandleClick(rest);
                        break;
                    case "move":
                        HandleMove(rest);
                        break;
                    case "down":
                        HandleMouseDownUp(rest, true);
                        break;
                    case "up":
                        HandleMouseDownUp(rest, false);
                        break;
                    case "scroll":
                        HandleScroll(rest);
                        break;
                    case "type":
                        HandleType(rest);
                        break;
                    case "key":
                        HandleKey(rest);
                        break;
                    default:
                        Console.WriteLine("ERROR: Unknown command: " + cmd);
                        break;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("ERROR: " + ex.Message);
            }
        }
    }

    static void HandleClick(string rest)
    {
        string[] parts = rest.Split(' ');
        if (parts.Length < 3) return;

        int x = int.Parse(parts[0]);
        int y = int.Parse(parts[1]);
        string btn = parts[2].ToLower();

        Point screenPt = new Point(x, y);
        IntPtr hWnd = WindowFromPoint(screenPt);
        if (hWnd == IntPtr.Zero) return;

        lastTargetHWnd = hWnd;

        Point clientPt = screenPt;
        ScreenToClient(hWnd, ref clientPt);

        IntPtr lParam = (IntPtr)((clientPt.Y << 16) | (clientPt.X & 0xFFFF));

        if (btn == "left")
        {
            PostMessage(hWnd, WM_LBUTTONDOWN, (IntPtr)1, lParam);
            Thread.Sleep(10);
            PostMessage(hWnd, WM_LBUTTONUP, (IntPtr)0, lParam);
        }
        else if (btn == "right" || btn == "rclick")
        {
            PostMessage(hWnd, WM_RBUTTONDOWN, (IntPtr)2, lParam);
            Thread.Sleep(10);
            PostMessage(hWnd, WM_RBUTTONUP, (IntPtr)0, lParam);
        }
        else if (btn == "double" || btn == "dblclick")
        {
            PostMessage(hWnd, WM_LBUTTONDOWN, (IntPtr)1, lParam);
            Thread.Sleep(10);
            PostMessage(hWnd, WM_LBUTTONUP, (IntPtr)0, lParam);
            Thread.Sleep(50);
            PostMessage(hWnd, WM_LBUTTONDOWN, (IntPtr)1, lParam);
            PostMessage(hWnd, WM_LBUTTONDBLCLK, (IntPtr)1, lParam);
            Thread.Sleep(10);
            PostMessage(hWnd, WM_LBUTTONUP, (IntPtr)0, lParam);
        }
    }

    static void HandleMove(string rest)
    {
        string[] parts = rest.Split(' ');
        if (parts.Length < 2) return;

        int x = int.Parse(parts[0]);
        int y = int.Parse(parts[1]);

        Point screenPt = new Point(x, y);
        IntPtr hWnd = WindowFromPoint(screenPt);
        if (hWnd == IntPtr.Zero) return;

        lastTargetHWnd = hWnd;

        Point clientPt = screenPt;
        ScreenToClient(hWnd, ref clientPt);

        IntPtr lParam = (IntPtr)((clientPt.Y << 16) | (clientPt.X & 0xFFFF));
        PostMessage(hWnd, WM_MOUSEMOVE, (IntPtr)0, lParam);
    }

    static void HandleMouseDownUp(string rest, bool isDown)
    {
        string[] parts = rest.Split(' ');
        if (parts.Length < 3) return;

        int x = int.Parse(parts[0]);
        int y = int.Parse(parts[1]);
        string btn = parts[2].ToLower();

        Point screenPt = new Point(x, y);
        IntPtr hWnd = WindowFromPoint(screenPt);
        if (hWnd == IntPtr.Zero) return;

        lastTargetHWnd = hWnd;

        Point clientPt = screenPt;
        ScreenToClient(hWnd, ref clientPt);

        IntPtr lParam = (IntPtr)((clientPt.Y << 16) | (clientPt.X & 0xFFFF));

        if (btn == "left")
        {
            PostMessage(hWnd, isDown ? WM_LBUTTONDOWN : WM_LBUTTONUP, isDown ? (IntPtr)1 : (IntPtr)0, lParam);
        }
        else if (btn == "right")
        {
            PostMessage(hWnd, isDown ? WM_RBUTTONDOWN : WM_RBUTTONUP, isDown ? (IntPtr)2 : (IntPtr)0, lParam);
        }
    }

    static void HandleScroll(string rest)
    {
        string[] parts = rest.Split(' ');
        if (parts.Length < 3) return;

        int x = int.Parse(parts[0]);
        int y = int.Parse(parts[1]);
        int delta = int.Parse(parts[2]); // raw delta, e.g. -120 or 120

        Point screenPt = new Point(x, y);
        IntPtr hWnd = WindowFromPoint(screenPt);
        if (hWnd == IntPtr.Zero) return;

        // WM_MOUSEWHEEL expects screen coordinates in lParam
        IntPtr wParam = (IntPtr)((delta << 16) & 0xFFFF0000);
        IntPtr lParam = (IntPtr)((y << 16) | (x & 0xFFFF));

        PostMessage(hWnd, WM_MOUSEWHEEL, wParam, lParam);
    }

    static void HandleType(string text)
    {
        IntPtr hWnd = GetTargetKeyboardWindow();
        if (hWnd == IntPtr.Zero) return;

        foreach (char c in text)
        {
            PostMessage(hWnd, WM_CHAR, (IntPtr)c, IntPtr.Zero);
            Thread.Sleep(5);
        }
    }

    static void HandleKey(string rest)
    {
        IntPtr hWnd = GetTargetKeyboardWindow();
        if (hWnd == IntPtr.Zero) return;

        string[] parts = rest.Split(' ');
        if (parts.Length < 1) return;

        string keyname = parts[0];
        bool ctrl = false, alt = false, shift = false, win = false;

        for (int i = 1; i < parts.Length; i++)
        {
            string mod = parts[i].ToLower();
            if (mod == "ctrl" || mod == "control") ctrl = true;
            else if (mod == "alt") alt = true;
            else if (mod == "shift") shift = true;
            else if (mod == "meta" || mod == "super" || mod == "win") win = true;
        }

        int vk = 0;
        if (VK_MAP.ContainsKey(keyname))
        {
            vk = VK_MAP[keyname];
        }
        else if (keyname.Length == 1)
        {
            vk = (int)char.ToUpper(keyname[0]);
        }

        if (vk == 0) return;

        SendKeyWithModifiers(hWnd, vk, ctrl, alt, shift, win);
    }

    static IntPtr GetTargetKeyboardWindow()
    {
        if (lastTargetHWnd != IntPtr.Zero) return lastTargetHWnd;
        return IntPtr.Zero;
    }

    static void SendKeyWithModifiers(IntPtr hWnd, int vk, bool ctrl, bool alt, bool shift, bool win)
    {
        if (ctrl) PostMessage(hWnd, WM_KEYDOWN, (IntPtr)VK_CONTROL, IntPtr.Zero);
        if (alt) PostMessage(hWnd, WM_SYSKEYDOWN, (IntPtr)VK_MENU, (IntPtr)0x20000000);
        if (shift) PostMessage(hWnd, WM_KEYDOWN, (IntPtr)VK_SHIFT, IntPtr.Zero);
        if (win) PostMessage(hWnd, WM_KEYDOWN, (IntPtr)VK_LWIN, IntPtr.Zero);

        uint msgDown = alt ? WM_SYSKEYDOWN : WM_KEYDOWN;
        uint msgUp = alt ? WM_SYSKEYUP : WM_KEYUP;
        IntPtr lParamDown = alt ? (IntPtr)0x20000000 : IntPtr.Zero;
        IntPtr lParamUp = alt ? (IntPtr)0x20000000 : IntPtr.Zero;

        PostMessage(hWnd, msgDown, (IntPtr)vk, lParamDown);
        Thread.Sleep(5);
        PostMessage(hWnd, msgUp, (IntPtr)vk, lParamUp);

        if (win) PostMessage(hWnd, WM_KEYUP, (IntPtr)VK_LWIN, IntPtr.Zero);
        if (shift) PostMessage(hWnd, WM_KEYUP, (IntPtr)VK_SHIFT, IntPtr.Zero);
        if (alt) PostMessage(hWnd, WM_SYSKEYUP, (IntPtr)VK_MENU, IntPtr.Zero);
        if (ctrl) PostMessage(hWnd, WM_KEYUP, (IntPtr)VK_CONTROL, IntPtr.Zero);
    }
}
