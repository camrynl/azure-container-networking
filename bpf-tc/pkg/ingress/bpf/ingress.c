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
#include <stdbool.h>

static __always_inline bool compare_ipv6_addr(const struct in6_addr *addr1, const struct in6_addr *addr2)
{
#pragma unroll
    for (int i = 0; i < sizeof(struct in6_addr); i++)
    {
        if (addr1->s6_addr[i] != addr2->s6_addr[i])
        {
            return false;
        }
    }
    return true;
}

SEC("classifier")
int linklocal_to_gua(struct __sk_buff *skb)
{
    // Define the global unicast address 2603:1062:0000:0001:fe80:1234:5678:9abc
    const struct in6_addr GLOBAL_UNICAST_ADDR = {{{0x26, 0x03, 0x10, 0x62, 0x00, 0x00, 0x00, 0x01, 0xfe, 0x80, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc}}};
    // Define the link-local address fe80::1234:5678:9abc
    const struct in6_addr LINKLOCAL_ADDR = {{{0xfe, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc}}};

    struct in6_addr src_addr;
    struct ipv6hdr ipv6_hdr;

    int ret = bpf_skb_load_bytes(skb, ETH_HLEN + offsetof(struct ipv6hdr, saddr), &src_addr, sizeof(src_addr));
    if (ret != 0)
    {
        bpf_printk("bpf_skb_load_bytes failed with error code %d.\n", ret);
        return TC_ACT_SHOT;
    }

    int ret_hdr = bpf_skb_load_bytes(skb, ETH_HLEN, &ipv6_hdr, sizeof(ipv6_hdr));
    if (ret_hdr != 0)
    {
        bpf_printk("bpf_skb_load_bytes failed with error code %d.\n", ret_hdr);
        return TC_ACT_SHOT;
    }

    // Check if the packet is TCP
    if (ipv6_hdr.nexthdr != IPPROTO_TCP)
        return TC_ACT_UNSPEC;

    // Check the source address to determine if it is Link Local
    if (compare_ipv6_addr(&src_addr, &LINKLOCAL_ADDR))
    {
        bpf_printk("Source address is a link local address. Setting new addr to global unicast.\n");
        bpf_printk("Source address is %pI6.\n", &src_addr);

        // Store the new source address in the packet
        int ret = bpf_skb_store_bytes(skb, ETH_HLEN + offsetof(struct ipv6hdr, saddr),
                                      &GLOBAL_UNICAST_ADDR, sizeof(GLOBAL_UNICAST_ADDR), BPF_F_RECOMPUTE_CSUM);
        if (ret != 0)
        {
            bpf_printk("bpf_skb_store_bytes failed with error code %d.\n", ret);
            return TC_ACT_SHOT;
        }
    }

    return TC_ACT_UNSPEC;
}

char __license[] SEC("license") = "Dual MIT/GPL";
