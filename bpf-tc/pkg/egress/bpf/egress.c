// go:build ignore
#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include <linux/pkt_cls.h>
#include <linux/if_ether.h>
#include <linux/ipv6.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <linux/if_ether.h>
#include <string.h>
#include <stdint.h>

SEC("classifier")
int gua_to_linklocal(struct __sk_buff *skb)
{
    // Define the link-local address fe80::1234:5678:9abc
    const struct in6_addr LINKLOCAL_ADDR = {{{0xfe, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc}}};

    // Check if the destination address is a global unicast address
    struct in6_addr dst_addr;

    int ret = bpf_skb_load_bytes(skb, ETH_HLEN + offsetof(struct ipv6hdr, daddr), &dst_addr, sizeof(dst_addr));
    if (ret != 0)
    {
        bpf_printk("bpf_skb_load_bytes failed with error code %d.\n", ret);
        return TC_ACT_SHOT;
    }

    // Check the first byte of the destination address to determine if it is a global unicast address
    if (dst_addr.s6_addr[0] == 0x26 && dst_addr.s6_addr[1] == 0x03 && dst_addr.s6_addr[2] == 0x10 && dst_addr.s6_addr[3] == 0x62)
    {

        bpf_printk("Destination address is a global unicast address. Setting new addr to link local.\n");

        // Store the new destination address in the packet
        int ret = bpf_skb_store_bytes(skb, ETH_HLEN + offsetof(struct ipv6hdr, daddr),
                                      &LINKLOCAL_ADDR, sizeof(LINKLOCAL_ADDR), BPF_F_RECOMPUTE_CSUM);
        if (ret != 0)
        {
            bpf_printk("bpf_skb_store_bytes failed with error code %d.\n", ret);
            return TC_ACT_SHOT;
        }
    }

    return TC_ACT_UNSPEC;
}

char __license[] SEC("license") = "Dual MIT/GPL";
