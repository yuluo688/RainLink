// Independent consumer probe for isolated libproxy 0.5.x acceptance tests.
// These stable public C signatures avoid importing GLib's development tree.
#include <stdio.h>
#include <stdlib.h>

typedef struct _pxProxyFactory pxProxyFactory;
extern pxProxyFactory *px_proxy_factory_new(void);
extern char **px_proxy_factory_get_proxies(pxProxyFactory *, const char *);
extern void px_proxy_factory_free(pxProxyFactory *);
extern void px_proxy_factory_free_proxies(char **);

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    pxProxyFactory *factory = px_proxy_factory_new();
    if (!factory) return 1;
    char **proxies = px_proxy_factory_get_proxies(factory, argv[1]);
    if (!proxies) {
        px_proxy_factory_free(factory);
        return 1;
    }
    for (size_t i = 0; proxies[i]; i++) puts(proxies[i]);
    px_proxy_factory_free_proxies(proxies);
    px_proxy_factory_free(factory);
    return 0;
}
