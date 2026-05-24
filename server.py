import asyncio
import socket
import threading
import json
import time
import sys

# Try to import necessary libraries, provide helpful guidance if missing
try:
    import pyautogui
    import websockets
except ImportError:
    print("\n[!] Missing required Python packages!")
    print("Please install them using pip:")
    print("    pip install pyautogui websockets\n")
    sys.exit(1)

# Disable pyautogui default pause to ensure real-time responsiveness
pyautogui.PAUSE = 0.0
# Disable failsafe (touchpads naturally hit corners, so we must prevent PyAutoGUI from crashing the connection on (0,0))
pyautogui.FAILSAFE = False

# Configuration
UDP_DISCOVERY_PORT = 8769
WEBSOCKET_PORT = 8765
UDP_BROADCAST_INTERVAL = 2.0  # seconds

def get_local_ip():
    """Get the active local IP address of the machine."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Connect to a dummy public IP to resolve local interface (doesn't send any traffic)
        s.connect(('8.8.8.8', 1))
        ip = s.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip

# Native Windows structures for SendInput (for Unicode key injection)
if sys.platform == 'win32':
    import ctypes
    WORD = ctypes.c_ushort
    DWORD = ctypes.c_ulong
    ULONG_PTR = ctypes.c_size_t

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [
            ("wVk", WORD),
            ("wScan", WORD),
            ("dwFlags", DWORD),
            ("time", DWORD),
            ("dwExtraInfo", ULONG_PTR),
        ]

    class MOUSEINPUT(ctypes.Structure):
        _fields_ = [
            ("dx", ctypes.c_long),
            ("dy", ctypes.c_long),
            ("mouseData", DWORD),
            ("dwFlags", DWORD),
            ("time", DWORD),
            ("dwExtraInfo", ULONG_PTR),
        ]

    class HARDWAREINPUT(ctypes.Structure):
        _fields_ = [
            ("uMsg", DWORD),
            ("wParamL", WORD),
            ("wParamH", WORD),
        ]

    class INPUT_UNION(ctypes.Union):
        _fields_ = [
            ("ki", KEYBDINPUT),
            ("mi", MOUSEINPUT),
            ("hi", HARDWAREINPUT),
        ]

    class INPUT(ctypes.Structure):
        _anonymous_ = ("u",)
        _fields_ = [
            ("type", DWORD),
            ("u", INPUT_UNION),
        ]

    INPUT_KEYBOARD = 1
    KEYEVENTF_UNICODE = 0x0004
    KEYEVENTF_KEYUP = 0x0002

    def send_unicode_string(text):
        """Injects a sequence of Unicode characters directly into the Windows OS input stream without using the clipboard."""
        if not text:
            return False
        try:
            n = len(text)
            # Create array of INPUT structures (press and release for each char)
            inputs = (INPUT * (2 * n))()
            for i, char in enumerate(text):
                codepoint = ord(char)
                # Press Event
                inputs[2 * i].type = INPUT_KEYBOARD
                inputs[2 * i].ki.wVk = 0
                inputs[2 * i].ki.wScan = codepoint
                inputs[2 * i].ki.dwFlags = KEYEVENTF_UNICODE
                inputs[2 * i].ki.time = 0
                inputs[2 * i].ki.dwExtraInfo = 0
                
                # Release Event
                inputs[2 * i + 1].type = INPUT_KEYBOARD
                inputs[2 * i + 1].ki.wVk = 0
                inputs[2 * i + 1].ki.wScan = codepoint
                inputs[2 * i + 1].ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP
                inputs[2 * i + 1].ki.time = 0
                inputs[2 * i + 1].ki.dwExtraInfo = 0
                
            num_sent = ctypes.windll.user32.SendInput(2 * n, ctypes.byref(inputs), ctypes.sizeof(INPUT))
            return num_sent == (2 * n)
        except Exception as e:
            print(f"[!] Error in send_unicode_string: {e}")
            return False


def udp_broadcast_worker():
    """Background thread to broadcast server existence for mobile auto-discovery."""
    print(f"[*] Auto-discovery broadcaster started on UDP port {UDP_DISCOVERY_PORT}...")
    
    # Setup UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    
    server_name = socket.gethostname()
    
    while True:
        try:
            local_ip = get_local_ip()
            payload = {
                "server_name": server_name,
                "ip": local_ip,
                "port": WEBSOCKET_PORT
            }
            message = json.dumps(payload).encode('utf-8')
            
            # Broadcast to the subnet
            sock.sendto(message, ('<broadcast>', UDP_DISCOVERY_PORT))
        except Exception as e:
            print(f"[!] UDP Broadcast error: {e}")
        
        time.sleep(UDP_BROADCAST_INTERVAL)

async def handle_client(websocket):
    """Handles incoming WebSocket connections and processes touchpad events."""
    client_ip = websocket.remote_address[0]
    print(f"[+] Client connected from {client_ip}")
    
    # Disable Nagle's algorithm (TCP_NODELAY) for ultra-low latency direct packet sending
    try:
        sock = websocket.transport.get_extra_info('socket')
        if sock is not None:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            print("[*] TCP_NODELAY enabled for connection.")
    except Exception as e:
        print(f"[!] Failed to set TCP_NODELAY: {e}")

    try:
        async for message in websocket:
            # Protocol: "type:param1:param2:..."
            parts = message.split(':', 2)
            if not parts:
                continue
                
            cmd_type = parts[0]
            
            # 1. Mouse Move: m:dx:dy
            if cmd_type == 'm' and len(parts) >= 3:
                try:
                    dx = float(parts[1])
                    dy = float(parts[2])
                    pyautogui.moveRel(dx, dy)
                except ValueError:
                    pass
                    
            # 2. Clicks: c:l or c:r
            elif cmd_type == 'c' and len(parts) >= 2:
                btn = 'left' if parts[1] == 'l' else 'right'
                pyautogui.click(button=btn)
                
            # 3. Scroll: s:dx:dy
            elif cmd_type == 's' and len(parts) >= 3:
                try:
                    dx = float(parts[1])
                    dy = float(parts[2])
                    
                    if sys.platform == 'win32':
                        import ctypes
                        # Native Windows smooth-scrolling using mouse_event
                        # Define argtypes if not already set to ensure proper signed int conversion
                        try:
                            if not hasattr(ctypes.windll.user32.mouse_event, 'argtypes') or ctypes.windll.user32.mouse_event.argtypes is None:
                                ctypes.windll.user32.mouse_event.argtypes = [
                                    ctypes.c_uint32,  # dwFlags
                                    ctypes.c_int32,   # dx
                                    ctypes.c_int32,   # dy
                                    ctypes.c_int32,   # dwData (signed int to support negative direction)
                                    ctypes.c_void_p   # dwExtraInfo
                                ]
                        except Exception:
                            pass
                            
                        # Vertical Scroll (MOUSEEVENTF_WHEEL = 0x0800)
                        if dy != 0:
                            # Multiply by standard WHEEL_DELTA (120) for reliable scrolling
                            ctypes.windll.user32.mouse_event(0x0800, 0, 0, int(dy * 120), 0)
                        # Horizontal Scroll (MOUSEEVENTF_HWHEEL = 0x01000)
                        if dx != 0:
                            # Multiply by standard WHEEL_DELTA (120) for reliable scrolling
                            ctypes.windll.user32.mouse_event(0x01000, 0, 0, int(dx * 120), 0)
                    else:
                        # Fallback for Mac/Linux (uses standard pyautogui)
                        if dy != 0:
                            pyautogui.scroll(int(dy * 15))
                        if dx != 0:
                            try:
                                pyautogui.hscroll(int(dx * 15))
                            except AttributeError:
                                pass
                except ValueError:
                    pass
                    
            # 4. Drag & Drop: d:s (start) or d:e (end)
            elif cmd_type == 'd' and len(parts) >= 2:
                action = parts[1]
                if action == 's':
                    pyautogui.mouseDown()
                elif action == 'e':
                    pyautogui.mouseUp()
                    
            # 5. Media keys: a:ACTION
            elif cmd_type == 'a' and len(parts) >= 2:
                action = parts[1]
                if action == 'volume_up':
                    pyautogui.press('volumeup')
                elif action == 'volume_down':
                    pyautogui.press('volumedown')
                elif action == 'mute':
                    pyautogui.press('volumemute')
                elif action == 'play_pause':
                    pyautogui.press('playpause')
                elif action == 'next':
                    pyautogui.press('nexttrack')
                elif action == 'prev':
                    pyautogui.press('prevtrack')
                    
            # 6. Keyboard: k:t:TEXT (text input) or k:k:KEY (special key)
            elif cmd_type == 'k' and len(parts) >= 3:
                sub_type = parts[1]
                payload = parts[2]
                if sub_type == 't':
                    if sys.platform == 'win32':
                        if not send_unicode_string(payload):
                            pyautogui.write(payload)
                    else:
                        pyautogui.write(payload)
                elif sub_type == 'k':
                    pyautogui.press(payload)
                    
            # 7. Ping/Latency test: p:TIMESTAMP
            elif cmd_type == 'p' and len(parts) >= 2:
                # Instantly echo back pong with timestamp
                await websocket.send(f"p:{parts[1]}")

    except websockets.exceptions.ConnectionClosed:
        print(f"[-] Client disconnected {client_ip}")
    except Exception as e:
        print(f"[!] Error handling client: {e}")
    finally:
        # Safety fallback - release mouse buttons if client disconnects while dragging
        try:
            pyautogui.mouseUp()
        except:
            pass

async def main():
    # Start the UDP broadcaster in a background daemon thread
    udp_thread = threading.Thread(target=udp_broadcast_worker, daemon=True)
    udp_thread.start()
    
    local_ip = get_local_ip()
    print(f"\n=========================================")
    print(f"🚀 TOUCHPAD SERVER IS RUNNING!")
    print(f"💻 Hostname: {socket.gethostname()}")
    print(f"🌐 Local IP: {local_ip}")
    print(f"🔌 WebSocket Port: {WEBSOCKET_PORT}")
    print(f"=========================================\n")
    print("[*] Listening for incoming touchpad connections...")
    
    async with websockets.serve(handle_client, "0.0.0.0", WEBSOCKET_PORT):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[-] Server stopped manually.")
