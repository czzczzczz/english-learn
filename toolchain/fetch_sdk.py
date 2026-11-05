import os, sys, time, urllib.request, zipfile

URL = "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/dotnet-sdk-10.0.403-win-x64.zip"
ROOT = os.path.dirname(os.path.abspath(__file__))
ZIP = os.path.join(ROOT, "dotnet-sdk-10.0.403-win-x64.zip")
DEST = os.path.join(ROOT, "dotnet")


def main():
    if not os.path.isdir(os.path.join(DEST, "sdk")):
        if not os.path.exists(ZIP) or os.path.getsize(ZIP) < 200 * 1024 * 1024:
            print("downloading", URL, flush=True)
            req = urllib.request.Request(URL, headers={"User-Agent": "dsh"})
            t0 = time.time()
            with urllib.request.urlopen(req, timeout=120) as r, open(ZIP, "wb") as f:
                total = int(r.headers.get("Content-Length") or 0)
                done = 0
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
                    done += len(chunk)
                    if done % (50 << 20) < (1 << 20):
                        print("  %.0f MB / %.0f MB  %.1f MB/s" % (
                            done / 1048576, total / 1048576, done / 1048576 / max(time.time() - t0, 0.1)), flush=True)
            print("downloaded %.1f MB in %.0fs" % (os.path.getsize(ZIP) / 1048576, time.time() - t0), flush=True)
        print("extracting...", flush=True)
        t0 = time.time()
        with zipfile.ZipFile(ZIP) as z:
            z.extractall(DEST)
        print("extracted in %.0fs" % (time.time() - t0), flush=True)
    print("DOTNET_ROOT=" + DEST, flush=True)
    os.system('"%s" --version' % os.path.join(DEST, "dotnet.exe"))


if __name__ == "__main__":
    sys.exit(main())
