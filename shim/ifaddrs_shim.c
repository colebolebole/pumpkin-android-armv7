// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * getifaddrs()/freeifaddrs() compatibility shim for Android API < 24.
 *
 * Bionic only exports these from API 24 (Android 7.0). This version enumerates
 * IPv4 interfaces through the ioctl interface (SIOCGIFCONF), which works on all
 * Android versions without needing netlink access.
 *
 * Limitation: IPv4 addresses only (no IPv6 entries are reported).
 */
#include <errno.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

#ifndef SOCK_CLOEXEC
#define SOCK_CLOEXEC 02000000
#endif

int getifaddrs(struct ifaddrs **ifap);
void freeifaddrs(struct ifaddrs *ifa);

/* One allocation per entry so freeifaddrs() can free each node directly. */
struct shim_entry {
    struct ifaddrs ifa;
    char name[IFNAMSIZ];
    struct sockaddr_in addr;
    struct sockaddr_in mask;
};

#define SHIM_MAX_IFACES 64

int getifaddrs(struct ifaddrs **ifap) {
    struct ifreq reqs[SHIM_MAX_IFACES];
    struct ifconf ifc;
    struct ifaddrs *head = NULL;
    struct ifaddrs **tail = &head;
    int fd, i, count;

    if (ifap == NULL) {
        errno = EINVAL;
        return -1;
    }
    *ifap = NULL;

    fd = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (fd < 0) {
        return -1;
    }

    memset(reqs, 0, sizeof(reqs));
    memset(&ifc, 0, sizeof(ifc));
    ifc.ifc_len = sizeof(reqs);
    ifc.ifc_req = reqs;
    if (ioctl(fd, SIOCGIFCONF, &ifc) < 0) {
        int saved = errno;
        close(fd);
        errno = saved;
        return -1;
    }

    count = (int)(ifc.ifc_len / sizeof(struct ifreq));
    for (i = 0; i < count; i++) {
        struct shim_entry *e;
        struct ifreq query;

        if (reqs[i].ifr_addr.sa_family != AF_INET) {
            continue;
        }

        e = (struct shim_entry *)calloc(1, sizeof(*e));
        if (e == NULL) {
            freeifaddrs(head);
            close(fd);
            errno = ENOMEM;
            return -1;
        }

        strncpy(e->name, reqs[i].ifr_name, IFNAMSIZ - 1);
        memcpy(&e->addr, &reqs[i].ifr_addr, sizeof(e->addr));
        e->addr.sin_family = AF_INET;

        memset(&query, 0, sizeof(query));
        strncpy(query.ifr_name, reqs[i].ifr_name, IFNAMSIZ - 1);
        if (ioctl(fd, SIOCGIFFLAGS, &query) == 0) {
            e->ifa.ifa_flags = (unsigned int)query.ifr_flags;
        }

        memset(&query, 0, sizeof(query));
        strncpy(query.ifr_name, reqs[i].ifr_name, IFNAMSIZ - 1);
        if (ioctl(fd, SIOCGIFNETMASK, &query) == 0) {
            memcpy(&e->mask, &query.ifr_addr, sizeof(e->mask));
            e->mask.sin_family = AF_INET;
            e->ifa.ifa_netmask = (struct sockaddr *)&e->mask;
        }

        e->ifa.ifa_name = e->name;
        e->ifa.ifa_addr = (struct sockaddr *)&e->addr;

        *tail = &e->ifa;
        tail = &e->ifa.ifa_next;
    }

    close(fd);
    *ifap = head;
    return 0;
}

void freeifaddrs(struct ifaddrs *ifa) {
    while (ifa != NULL) {
        struct ifaddrs *next = ifa->ifa_next;
        free(ifa);
        ifa = next;
    }
}
