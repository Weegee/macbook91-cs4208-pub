/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * Host-side regression tests for the MacBook9,1 (A1534) target-device gate.
 *
 * These compile the *same* header the kernel module uses, so they exercise the
 * real decision logic rather than re-describing it. No kernel required.
 *
 *   cc -Wall -Wextra -Werror -o test_a1534_match test_a1534_match.c
 */

#include <stdio.h>
#include <string.h>

#include "../src/cs420x-a1534/a1534_match.h"

static int streq(const char *a, const char *b) { return strcmp(a, b) == 0; }

static int failures;
static int checks;

static void expect(const char *what, int got, int want)
{
	checks++;
	if (got == want) {
		printf("  ok    %-58s -> %d\n", what, got);
	} else {
		failures++;
		printf("  FAIL  %-58s -> %d (want %d)\n", what, got, want);
	}
}

int main(void)
{
	puts("A1534 target-device gate");

	/*
	 * The case the project's matching rules name explicitly:
	 * PCI subsystem 8086:7270, codec subsystem 106b:6500,
	 * DMI Apple Inc. / MacBook9,1  =>  must select A1534.
	 *
	 * The PCI subsystem is absent from the gate by design; this test
	 * documents that the Intel PCI id does not prevent the match.
	 */
	expect("MacBook9,1 + 106b:6500 (PCI is 8086:7270)",
	       a1534_match(0x106b6500, "Apple Inc.", "MacBook9,1", streq), 1);

	/* Other CS4208 Macs must keep untouched mainline behaviour. */
	expect("MacBookPro11,2 codec SSID 106b:5e00",
	       a1534_match(0x106b5e00, "Apple Inc.", "MacBookPro11,2", streq), 0);
	expect("MacBookAir6,2 codec SSID 106b:7200",
	       a1534_match(0x106b7200, "Apple Inc.", "MacBookAir6,2", streq), 0);
	expect("MacMini7,1 codec SSID 106b:6c00",
	       a1534_match(0x106b6c00, "Apple Inc.", "Macmini7,1", streq), 0);
	expect("iMac16,1 codec SSID 106b:7f00",
	       a1534_match(0x106b7f00, "Apple Inc.", "iMac16,1", streq), 0);

	/*
	 * Right SSID but wrong machine, and right machine but wrong SSID.
	 * Both halves of the gate must be load-bearing.
	 */
	expect("right SSID, wrong product",
	       a1534_match(0x106b6500, "Apple Inc.", "MacBookAir7,2", streq), 0);
	expect("right SSID, wrong vendor",
	       a1534_match(0x106b6500, "Acme Inc.", "MacBook9,1", streq), 0);
	expect("right machine, wrong SSID",
	       a1534_match(0x106b5e00, "Apple Inc.", "MacBook9,1", streq), 0);

	/*
	 * Subsystem-id loss. Measured on the test machine after a PCI remove/rescan of the
	 * audio controller: the codec reported Subsystem Id 0x10134208, its own
	 * vendor/device id, because the firmware-written value was gone. The
	 * gate stopped matching, the driver silently took the generic path, and
	 * hw:0,0 became a 2-channel device - so every 4-channel playback failed
	 * with "channel count not supported" and was misread as silence.
	 *
	 * On the right machine that must still match. On any other machine it
	 * must not, and the DMI check is what guarantees that.
	 */
	expect("MacBook9,1 with the SSID lost (reads as the CS4208 vendor id)",
	       a1534_match(0x10134208, "Apple Inc.", "MacBook9,1", streq), 1);
	expect("SSID lost, but a different Apple machine",
	       a1534_match(0x10134208, "Apple Inc.", "MacBookAir7,2", streq), 0);
	expect("SSID lost, non-Apple machine",
	       a1534_match(0x10134208, "Acme Inc.", "MacBook9,1", streq), 0);
	expect("SSID lost and DMI unreadable",
	       a1534_match(0x10134208, NULL, NULL, streq), 0);
	expect("a different Cirrus codec id on the right machine",
	       a1534_match(0x10134206, "Apple Inc.", "MacBook9,1", streq), 0);

	/*
	 * The PCI subsystem id of this machine is 8086:7270. If anyone ever
	 * reintroduces PCI-subsystem matching, these guard that 8086:7270 is
	 * not treated as an Apple model id (docs/ROOT-CAUSE.md §3).
	 */
	expect("codec SSID accidentally set to the PCI subsystem 8086:7270",
	       a1534_match(0x80867270, "Apple Inc.", "MacBook9,1", streq), 0);

	/* Fail closed when DMI is unreadable rather than guessing. */
	expect("DMI vendor NULL",
	       a1534_match(0x106b6500, NULL, "MacBook9,1", streq), 0);
	expect("DMI product NULL",
	       a1534_match(0x106b6500, "Apple Inc.", NULL, streq), 0);
	expect("both DMI fields NULL",
	       a1534_match(0x106b6500, NULL, NULL, streq), 0);
	expect("no comparison function",
	       a1534_match(0x106b6500, "Apple Inc.", "MacBook9,1", NULL), 0);

	/* Substring and case must not match: DMI values are exact. */
	expect("product is a prefix of the target",
	       a1534_match(0x106b6500, "Apple Inc.", "MacBook9", streq), 0);
	expect("product has trailing text",
	       a1534_match(0x106b6500, "Apple Inc.", "MacBook9,10", streq), 0);
	expect("product differs in case",
	       a1534_match(0x106b6500, "Apple Inc.", "macbook9,1", streq), 0);
	expect("empty strings",
	       a1534_match(0x106b6500, "", "", streq), 0);

	printf("\n%d checks, %d failures\n", checks, failures);
	return failures ? 1 : 0;
}
