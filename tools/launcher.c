#include <mach-o/dyld.h>
#include <limits.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

int main(int argc, char **argv) {
    char executable[PATH_MAX], resolved[PATH_MAX], base[PATH_MAX], resources[PATH_MAX], data[PATH_MAX];
    uint32_t n = sizeof(executable);
    if (_NSGetExecutablePath(executable, &n) != 0 || !realpath(executable,resolved)) return 1;
    strcpy(base,resolved); *strrchr(base,'/')=0;
    snprintf(resources,sizeof(resources),"%s/../Resources",base);
    const char *custom=getenv("AGENT_STUDIO_DATA");
    if(custom && *custom) snprintf(data,sizeof(data),"%s",custom);
    else snprintf(data,sizeof(data),"%s/Library/Application Support/Agent Studio",getenv("HOME"));
    // mkdirs, without invoking a shell or interpolating user-controlled paths.
    char partial[PATH_MAX];snprintf(partial,sizeof(partial),"%s",data);
    for(char *p=partial+1;*p;p++)if(*p=='/'){*p=0;mkdir(partial,0700);*p='/';}
    mkdir(partial,0700);
    char node[PATH_MAX], engine[PATH_MAX], pack[PATH_MAX], log[PATH_MAX];
    snprintf(node,sizeof(node),"%s/runtime/node",resources);
    snprintf(engine,sizeof(engine),"%s/GodotEngine",base);
    snprintf(pack,sizeof(pack),"%s/game.pck",resources);
    snprintf(log,sizeof(log),"%s/game.log",data);
    setenv("AGENT_STUDIO_ROOT",resources,1);setenv("AGENT_STUDIO_DATA",data,1);setenv("AGENT_STUDIO_NODE",node,1);
    const char *oldpath=getenv("PATH");char process_path[8192];
    snprintf(process_path,sizeof(process_path),"%s/runtime:%s",resources,oldpath?oldpath:"/usr/bin:/bin");setenv("PATH",process_path,1);
    char *args[argc+10];int i=0;
    args[i++]=engine;args[i++]="--main-pack";args[i++]=pack;args[i++]="--log-file";args[i++]=log;args[i++]="--";
    if(getenv("AGENT_STUDIO_OFFLINE"))args[i++]="--no-bridge";
    for(int j=1;j<argc;j++)args[i++]=argv[j];args[i]=NULL;
    execv(engine,args);perror("Agent Studio 启动失败");return 1;
}
