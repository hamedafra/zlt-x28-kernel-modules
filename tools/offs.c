/* Compile-only helper: records the struct offsets BBR depends on, so they can be
 * read out of the .o with objdump and compared with the router kernel's code. */
#include <linux/module.h>
#include <linux/tcp.h>
#include <net/tcp.h>
#include <net/inet_connection_sock.h>

#define O(s, f) offsetof(struct s, f)
#define ENTRY(name, val) { name, val }
struct ent { const char *name; unsigned long val; };

static const struct ent offs[] __used = {
	ENTRY("tcp_sock.snd_ssthresh", O(tcp_sock, snd_ssthresh)),
	ENTRY("tcp_sock.snd_cwnd", O(tcp_sock, snd_cwnd)),
	ENTRY("tcp_sock.snd_cwnd_clamp", O(tcp_sock, snd_cwnd_clamp)),
	ENTRY("tcp_sock.mss_cache", O(tcp_sock, mss_cache)),
	ENTRY("tcp_sock.srtt_us", O(tcp_sock, srtt_us)),
	ENTRY("tcp_sock.packets_out", O(tcp_sock, packets_out)),
	ENTRY("tcp_sock.delivered", O(tcp_sock, delivered)),
	ENTRY("tcp_sock.delivered_mstamp", O(tcp_sock, delivered_mstamp)),
	ENTRY("tcp_sock.lost", O(tcp_sock, lost)),
	ENTRY("tcp_sock.app_limited", O(tcp_sock, app_limited)),
	ENTRY("tcp_sock.prior_cwnd", O(tcp_sock, prior_cwnd)),
	ENTRY("tcp_sock.snd_nxt", O(tcp_sock, snd_nxt)),
	ENTRY("tcp_sock.tcp_mstamp", O(tcp_sock, tcp_mstamp)),
	ENTRY("tcp_sock.rtt_min", O(tcp_sock, rtt_min)),
	ENTRY("tcp_sock.data_segs_out", O(tcp_sock, data_segs_out)),
	ENTRY("tcp_sock.tcp_tx_delay_placeholder", 0),
	ENTRY("sock.sk_pacing_rate", O(sock, sk_pacing_rate)),
	ENTRY("sock.sk_max_pacing_rate", O(sock, sk_max_pacing_rate)),
	ENTRY("sock.sk_pacing_status", O(sock, sk_pacing_status)),
	ENTRY("sock.sk_pacing_shift", O(sock, sk_pacing_shift)),
	ENTRY("sock.sk_gso_max_segs", O(sock, sk_gso_max_segs)),
	ENTRY("icsk.icsk_ca_priv", O(inet_connection_sock, icsk_ca_priv)),
	ENTRY("icsk.icsk_ca_ops", O(inet_connection_sock, icsk_ca_ops)),
	ENTRY("sizeof.rate_sample", sizeof(struct rate_sample)),
	ENTRY("rate_sample.prior_delivered", O(rate_sample, prior_delivered)),
	ENTRY("rate_sample.delivered", O(rate_sample, delivered)),
	ENTRY("rate_sample.interval_us", O(rate_sample, interval_us)),
	ENTRY("rate_sample.rtt_us", O(rate_sample, rtt_us)),
	ENTRY("rate_sample.losses", O(rate_sample, losses)),
	ENTRY("rate_sample.acked_sacked", O(rate_sample, acked_sacked)),
	ENTRY("rate_sample.prior_in_flight", O(rate_sample, prior_in_flight)),
	ENTRY("rate_sample.is_app_limited", O(rate_sample, is_app_limited)),
	ENTRY("sizeof.tcp_congestion_ops", sizeof(struct tcp_congestion_ops)),
	ENTRY("tcp_congestion_ops.init", O(tcp_congestion_ops, init)),
	ENTRY("tcp_congestion_ops.ssthresh", O(tcp_congestion_ops, ssthresh)),
	ENTRY("tcp_congestion_ops.cong_control", O(tcp_congestion_ops, cong_control)),
	ENTRY("tcp_congestion_ops.undo_cwnd", O(tcp_congestion_ops, undo_cwnd)),
	ENTRY("tcp_congestion_ops.name", O(tcp_congestion_ops, name)),
	ENTRY("tcp_congestion_ops.owner", O(tcp_congestion_ops, owner)),
	ENTRY("sizeof.minmax", sizeof(struct minmax)),
	ENTRY("sizeof.module", sizeof(struct module)),
};

/* print the table from the object: objdump -s -j .rodata offs.o is awkward, so also emit it as asm comments */
#define ASM_ENTRY(n, v) asm volatile(".ascii \"OFFS " n "=%0\\n\"" :: "i"(v))
void __used offs_emit(void)
{
	int i;
	for (i = 0; i < ARRAY_SIZE(offs); i++)
		;
}
