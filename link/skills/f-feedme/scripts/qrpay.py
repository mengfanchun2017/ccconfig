#!/usr/bin/env python3
"""Display payment QR code as ASCII art in terminal."""
import sys

def show_qr(url):
    """Generate and print ASCII QR code to terminal."""
    try:
        import qrcode
        qr = qrcode.QRCode(
            version=2,
            error_correction=qrcode.constants.ERROR_CORRECT_M,
            box_size=1,
            border=2,
        )
        qr.add_data(url)
        qr.make(fit=True)
        try:
            qr.print_ascii(tty=True)
        except OSError:
            qr.print_ascii(tty=False)
        return True
    except ImportError:
        print("[!] qrcode module not installed. Run: pip3 install qrcode", file=sys.stderr)
        return False

if __name__ == '__main__':
    url = sys.argv[1] if len(sys.argv) > 1 else None
    if not url:
        print("usage: qrpay.py <pay_url>", file=sys.stderr)
        sys.exit(1)

    print()
    print("=" * 52)
    print("  扫描二维码支付")
    print("=" * 52)
    print()

    show_qr(url)

    print()
    print(f"  支付链接: {url}")
    print()
    print("=" * 52)
    print("  手机扫码完成支付，或点击上方链接")
    print("=" * 52)
