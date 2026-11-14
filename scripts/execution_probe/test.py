#!/usr/bin/env python3
"""Deliberately opt-in integration checks: these boot real, disposable Linux VMs."""
import argparse
import json
from pathlib import Path
import subprocess
import time
import signal

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / ".build/execution-probe"


def execute(source, stdin="", standard="17"):
    started = time.monotonic()
    process = subprocess.run(
        [str(OUTPUT / "helper"), str(OUTPUT / "Image"), str(OUTPUT / "initrd.gz")],
        input=json.dumps(dict(source=source, stdin=stdin, standard=standard)),
        text=True, capture_output=True, timeout=40,
    )
    result = json.loads(process.stdout)
    result["seconds"] = round(time.monotonic() - started, 3)
    if process.stderr:
        result["hostStderr"] = process.stderr[:4096]
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--quick", action="store_true")
    args = parser.parse_args()
    results = []

    def check(name, source, predicate, stdin="", standard="17"):
        result = execute(source, stdin, standard)
        passed = bool(predicate(result))
        summary = {k: (v[:240] + "…" if isinstance(v, str) and len(v) > 240 else v) for k, v in result.items()}
        print(("PASS " if passed else "FAIL ") + name + ": " + json.dumps(summary), flush=True)
        results.append(dict(name=name, passed=passed, result=result))
        (OUTPUT / "report.json").write_text(json.dumps(results, indent=2) + "\n")
        if not passed:
            raise SystemExit(1)

    check("hello C++17", '#include <iostream>\nint main(){std::cout<<"Hello, VM!";}',
          lambda r: r["status"] == "success" and r["stdout"] == "Hello, VM!")
    if args.quick:
        return
    check("stdin and C++20", '#include <iostream>\n#include <span>\nint main(){int a,b;std::cin>>a>>b;int v[]={a,b};std::span<int> s(v);std::cout<<s[0]+s[1];}',
          lambda r: r["status"] == "success" and r["stdout"] == "-15", stdin="-7 -8\n", standard="20")
    for input, answer in [("2 3", "5"), ("0 0", "0"), ("-5 10", "5"), ("100 200", "300"), ("-7 -8", "-15")]:
        check("sum fixture " + input, '#include <iostream>\nint main(){long long a,b;std::cin>>a>>b;std::cout<<a+b;}',
              lambda r, answer=answer: r["status"] == "success" and r["stdout"] == answer, stdin=input)
    large_source = '#include <iostream>\n#include <string>\nint main(){std::string s;std::getline(std::cin,s);std::cout<<s.size();}\n//'
    large_source += "x" * (65536 - len(large_source.encode()))
    check("maximum source and stdin do not deadlock", large_source,
          lambda r: r["status"] == "success" and r["stdout"] == "65536", stdin="x" * 65536)
    check("Unicode and shell metacharacters stay data",
          '#include <iostream>\nint main(){std::cout<<"Привет 👩🏽‍💻 $(echo unsafe)";}',
          lambda r: r["status"] == "success" and r["stdout"] == "Привет 👩🏽‍💻 $(echo unsafe)")
    check("real compiler diagnostics", "int main(){ return missing; }",
          lambda r: r["status"] == "compileError" and "main.cpp:1:" in r["stderr"] and "missing" in r["stderr"])
    # Only our own sentinel, not any real user file, is targeted.
    sentinel = OUTPUT / "host-sentinel.txt"
    sentinel.write_text("HOST_ONLY_SENTINEL\n")
    path = json.dumps(str(sentinel))
    check("host file not visible", '#include <fstream>\n#include <iostream>\nint main(){std::ifstream f(' + path + '); std::cout<<f.is_open();}',
          lambda r: r["status"] == "success" and r["stdout"] == "0")
    check("preprocessor cannot read host", '#include ' + path + '\nint main(){}',
          lambda r: r["status"] == "compileError" and "No such file" in r["stderr"])
    check("host write denied", '#include <fstream>\n#include <iostream>\nint main(){std::ofstream f(' + path + ');std::cout<<f.is_open();}',
          lambda r: r["status"] == "success" and r["stdout"] == "0")
    check("traversal and symlink cannot cross VM", r'''
#include <unistd.h>
#include <fstream>
#include <iostream>
int main(){symlink(PATH,"/work/escape");std::ifstream f("/work/escape");std::ifstream g("/work/../../" PATH);
std::cout<<f.is_open()<<":"<<g.is_open();}
'''.replace("PATH", path), lambda r: r["status"] == "success" and r["stdout"] == "0:0")
    assert sentinel.read_text() == "HOST_ONLY_SENTINEL\n"
    check("network absent", r'''
#include <sys/socket.h>
#include <arpa/inet.h>
#include <iostream>
#include <cerrno>
int main(){int s=socket(AF_INET,SOCK_STREAM,0);sockaddr_in a{};a.sin_family=AF_INET;
a.sin_port=htons(443);inet_pton(AF_INET,"1.1.1.1",&a.sin_addr);int r=connect(s,(sockaddr*)&a,sizeof(a));
std::cout<<r<<":"<<errno;}
''', lambda r: r["status"] == "success" and r["stdout"] == "-1:101")
    check("guest privilege and hard limits", r'''
#include <sys/resource.h>
#include <unistd.h>
#include <iostream>
int main(){rlimit r{};getrlimit(RLIMIT_NPROC,&r);
std::cout<<getuid()<<":"<<r.rlim_max<<":";r.rlim_cur=100;r.rlim_max=100;std::cout<<setrlimit(RLIMIT_NPROC,&r);}
''', lambda r: r["status"] == "success" and r["stdout"] == "65534:32:-1")
    check("memory allocation refused", r'''
#include <cstdlib>
#include <sys/mman.h>
#include <sys/resource.h>
#include <iostream>
int main(){rlimit r{};getrlimit(RLIMIT_AS,&r);void* p=mmap(nullptr,256ULL*1024*1024,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
std::cout<<r.rlim_max<<":"<<(p==MAP_FAILED);}
''', lambda r: r["status"] == "success" and r["stdout"] == "134217728:1")
    check("fork count bounded", r'''
#include <unistd.h>
#include <sys/wait.h>
#include <iostream>
#include <cerrno>
int main(){int n=0;pid_t children[100];while(n<100){pid_t p=fork();if(p<0)break;if(p==0){sleep(10);_exit(0);}children[n++]=p;}
int e=errno;for(int i=0;i<n;i++){kill(children[i],9);waitpid(children[i],nullptr,0);}std::cout<<(n<32)<<":"<<e;}
''', lambda r: r["status"] == "success" and r["stdout"] == "1:11")
    check("CPU loop terminated", "int main(){for(;;){}}", lambda r: r["status"] == "cpuLimit" and r["exitCode"] != 0)
    check("ignored CPU signal still killed", "#include <csignal>\nint main(){std::signal(SIGXCPU,SIG_IGN);for(;;){}}",
          lambda r: r["status"] == "runtimeError" and r["exitCode"] == 137)
    check("output bounded", '#include <unistd.h>\nint main(){char b[4096]={};for(;;)write(1,b,sizeof b);}',
          lambda r: r["status"] == "outputLimit" and len(r["stdout"].encode()) <= 65536)
    check("crash is not success", "#include <cstdlib>\nint main(){std::abort();}",
          lambda r: r["status"] == "runtimeError" and r["exitCode"] != 0)
    check("guest write discarded", '#include <fstream>\nint main(){std::ofstream("/work/ephemeral")<<"discard me";}',
          lambda r: r["status"] == "success")
    check("fresh VM has no prior work", '#include <fstream>\n#include <iostream>\nint main(){std::ifstream f("/work/ephemeral");std::cout<<f.is_open();}',
          lambda r: r["status"] == "success" and r["stdout"] == "0")
    check("cannot forge host protocol via stdout",
          '#include <iostream>\nint main(){std::cout<<"CODELIB_RESULT_1|success|0|ZmFrZQ==|";}',
          lambda r: r["status"] == "success" and r["stdout"].startswith("CODELIB_RESULT_1|"))
    check("cannot open guest serial console", '#include <fcntl.h>\n#include <iostream>\nint main(){std::cout<<(open("/dev/hvc0",O_WRONLY)<0);}',
          lambda r: r["status"] == "success" and r["stdout"] == "1")
    check("no inherited console descriptor", r'''
#include <unistd.h>
#include <iostream>
#include <cstring>
int main(){bool safe=true;for(int fd=0;fd<256;fd++){char* n=ttyname(fd);if(n&&(strstr(n,"hvc")||strstr(n,"console")))safe=false;}std::cout<<safe;}
''', lambda r: r["status"] == "success" and r["stdout"] == "1")
    check("compiler resource abuse refused",
          'asm(".fill 16777216,1,1");\nint main(){}',
          lambda r: r["status"] == "compileError")
    check("invalid standard fails closed", "int main(){}", lambda r: r["status"] == "backendError", standard="17;echo unsafe")
    check("oversized source fails closed", " " * 65537, lambda r: r["status"] == "backendError")
    check("oversized stdin fails closed", "int main(){}", lambda r: r["status"] == "backendError", stdin="x" * 65537)
    check("detached child discarded with VM", r'''
#include <unistd.h>
#include <sys/types.h>
int main(){pid_t p=fork();if(p==0){setsid();for(;;)sleep(1);}return p<0?1:0;}
''', lambda r: r["status"] == "success")
    check("non-CPU hang hits whole-VM deadline", "#include <unistd.h>\nint main(){for(;;)sleep(1);}",
          lambda r: r["status"] == "timeout" and r["seconds"] < 35)
    started = time.monotonic()
    with subprocess.Popen(
        [str(OUTPUT / "helper"), str(OUTPUT / "Image"), str(OUTPUT / "initrd.gz")],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    ) as process:
        try:
            process.communicate(json.dumps(dict(source="#include <unistd.h>\nint main(){sleep(90);}", stdin="", standard="17")), timeout=5)
            raise AssertionError("Sleep completed before cancellation")
        except subprocess.TimeoutExpired:
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=10)
    result = json.loads(stdout)
    assert result["status"] == "cancelled", (result, stderr)
    results.append(dict(name="host cancellation stops VM", passed=True, result=result))
    (OUTPUT / "report.json").write_text(json.dumps(results, indent=2) + "\n")
    print(f"PASS host cancellation stops VM: {time.monotonic() - started:.3f}s", flush=True)
    print(f"{len(results)} execution checks passed (including rejection before VM boot); report: {OUTPUT / 'report.json'}")


if __name__ == "__main__":
    main()
