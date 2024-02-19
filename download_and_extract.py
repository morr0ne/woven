import httpx
import tarfile
from rich.progress import (
    Progress,
    BarColumn,
    DownloadColumn,
    TransferSpeedColumn,
    MofNCompleteColumn,
)
import os
import shutil

os.makedirs("sources/tar", exist_ok=True)


def download_file(url: str, file_name: str, pretty_name: str):
    with open(f"sources/tar/{file_name}", "wb") as file:
        with httpx.stream("GET", url, follow_redirects=True, timeout=None) as response:
            total = 0

            try:
                total = int(response.headers["Content-Length"])
            except:
                pass

            with Progress(
                "{task.description} [progress.percentage]{task.percentage:>3.0f}%",
                BarColumn(bar_width=None),
                DownloadColumn(),
                TransferSpeedColumn(),
            ) as progress:
                download_task = progress.add_task(
                    f"Downloading {pretty_name}", total=total
                )
                for chunk in response.iter_bytes():
                    file.write(chunk)
                    progress.update(
                        download_task, completed=response.num_bytes_downloaded
                    )


def extract_file(file_name: str, path: str, pretty_name: str):
    try:
        shutil.rmtree(path)
        print("Removing old extracted sources...")
    except:
        pass

    with tarfile.open(f"sources/tar/{file_name}") as tar:
        members = tar.getmembers()
        with Progress(
            "{task.description} [progress.percentage]{task.percentage:>3.0f}%",
            BarColumn(bar_width=None),
            MofNCompleteColumn(),
        ) as progress:
            extract_task = progress.add_task(
                f"Extracting {pretty_name}", total=len(members)
            )
            for member in members:
                tar.extract(member, path)
                progress.update(extract_task, advance=1)


def check_hash(path: str, hash: str) -> bool:
    return os.popen(f"b3sum --no-names {path}").read().strip() == hash


sources = [
    (
        "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.7.5.tar.xz",
        "linux.tar.xz",
        "sources/linux",
        "linux kernel sources",
        "125bed4991990ef8b7ce3629341e3ec28eb04c1c9f0452787e0f42ce525497a4",
    ),
    (
        "http://sources.buildroot.net/busybox/busybox-1.36.1.tar.bz2",
        "busybox.tar.bz2",
        "sources/busybox",
        "busybox sources",
        "dfdfc1b9aa41d5134e087d904c0a5f6958825f0e94db1d2cb5ea93088247c886",
    ),
    (
        "https://git.kernel.org/pub/scm/utils/dash/dash.git/snapshot/dash-0.5.12.tar.gz",
        "dash.tar.gz",
        "sources/dash",
        "dash sources",
        "f38a283332d2b34058112fe4f06d2148f2318610e08ad23bd70c2e206db505eb",
    ),
    (
        "https://github.com/limine-bootloader/limine/releases/download/v7.0.5/limine-7.0.5.tar.xz",
        "limine.tar.xz",
        "sources/limine",
        "limine sources",
        "1c2fa29c9ddfa510a338ccb6b8764b9acdf948405f231e2ef316a03a1f04a7e0",
    ),
    (
        "https://cdn.kernel.org/pub/tools/llvm/files/llvm-17.0.6-x86_64.tar.xz",
        "llvm.tar.xz",
        "tools/llvm",
        "llvm sources",
        "1690e309a0261c42f042eedf9b968c64e4c21e49d99b835b0a3c530daae441e5",
    ),
    # (
    #     "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/snapshot/linux-firmware-20240115.tar.gz",
    #     "linux-firmware.tar.xz",
    #     "sources/linux-firmware",
    #     "linux firmware sources",
    #     "b804c22a56dbefc7e291ef69c295651e71d1c9c808795f9ce09aba2debf9ce14",
    # ),
]


for url, file_name, path, pretty_name, hash in sources:
    if os.path.isfile(f"sources/tar/{file_name}") and check_hash(
        f"sources/tar/{file_name}", hash
    ):
        print(f"File {file_name} exists already, skipping download")
    else:
        download_file(url, file_name, pretty_name)

    extract_file(file_name, path, pretty_name)
