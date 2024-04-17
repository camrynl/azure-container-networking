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
int linklocal_to_gua(struct __sk_buff *skb)
{
    const struct in6_addr GLOBAL_UNICAST_ADDR = {{{0x26, 0x03, 0x10, 0x62, 0x00, 0x00, 0x00, 0x01, 0xfe, 0x80, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc}}};
    struct in6_addr src_addr;
    struct in6_addr new_src_addr;

    int ret = bpf_skb_load_bytes(skb, ETH_HLEN + offsetof(struct ipv6hdr, saddr), &src_addr, sizeof(src_addr));
    if (ret != 0)
    {
        bpf_printk("bpf_skb_load_bytes failed with error code %d.\n", ret);
        return TC_ACT_SHOT;
    }

    // Check the bytes of the source address to determine if it is Link Local
    if (src_addr.s6_addr[0] == 0xfe && src_addr.s6_addr[1] == 0x80 && src_addr.s6_addr[10] == 0x12 && src_addr.s6_addr[11] == 0x34)
    {

        bpf_printk("Source address is a link local address. Setting new addr to global unicast.\n");

        // Store the new source address in the packet
        int ret = bpf_skb_store_bytes(skb, ETH_HLEN + offsetof(struct ipv6hdr, saddr),
                                      &GLOBAL_UNICAST_ADDR, sizeof(GLOBAL_UNICAST_ADDR), BPF_F_RECOMPUTE_CSUM);
        if (ret != 0)
        {
            bpf_printk("bpf_skb_store_bytes failed with error code %d.\n", ret);
            return TC_ACT_SHOT;
        }
        bpf_skb_load_bytes(skb, ETH_HLEN + offsetof(struct ipv6hdr, saddr), &new_src_addr, sizeof(new_src_addr));
        for (int i = 0; i < sizeof(new_src_addr.s6_addr); i++)
        {
            bpf_printk("%02x", new_src_addr.s6_addr[i]);
        }
    }

    return TC_ACT_UNSPEC;
}

char __license[] SEC("license") = "Dual MIT/GPL";
