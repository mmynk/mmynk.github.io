% Netlink in Rust: part 1 aka ethtool
% November 23, 2023

Over the past few months, my day job has led me to explore some of the low-level networking tools available in Linux, specifically `ethtool` and `tc`. I've also had to learn a bit about Netlink, the kernel API underpinning these tools. This post serves as a summary of my learnings.

# Netlink

`netlink(7)` is essentially a fancier version of the `ioctl(2)` system call, allowing userspace programs to communicate with the kernel. It is the backbone for various tools like `iproute2`, `ethtool`, and `tc`. I won't dive into the specifics of how it works here, but the [kernel documentation](https://docs.kernel.org/userspace-api/netlink/intro.html) is a detailed, albeit overwhelming, resource.

## Netlink in Rust

There are not many Rust libraries for interacting with Netlink. The most mature one appears to be a combination of crates under [rust-netlink](https://github.com/rust-netlink). It's worth noting that this entire project, consisting of 21 repositories, is maintained by a single person, which is a bit concerning.

My initial use case involved fetching settings and stats of network interfaces, essentially mimicking `ethtool(8)`. We use this wonderful tool called [below](https://github.com/facebookincubator/below) to monitor and record historical system data. It is written in Rust and we wanted to enhance the library to record network interface stats, basically the output of `ethtool -S <interface>`.

# `ethtool` in Rust

I began by looking for libraries in Rust that could help me with this task. The above project also has a [ethtool](https://github.com/rust-netlink/ethtool) crate but it only supports a subset of the features. Then I turned to the kernel documentation for [netlink interface for ethtool](https://docs.kernel.org/networking/ethtool-netlink.html). However, for someone with zero experience in kernel programming, it proved to be quite overwhelming. After a few hours of trial and error, I decided to look at other options and stumbled upon the `ioctl(2)` and could not help but be amazed at the simplicity of the tool. I put together a quick and dirty [implementation](https://github.com/mmynk/rustuff/tree/main/ethtool) and it worked like a charm.

My initial version, though functional, had its share of issues. For instance, I was redefining C types and passing them down to the kernel. Following is a snippet from my early snippet which defines `ethtool_stats` struct from `uapi/linux/ethtool.h` and passes it down to the kernel to load the stats.

```rust
use nix::libc;

const ETH_SS_STATS: u32 = 0x1;

#[repr(C)]
struct IfReq {
    if_name: [u8; IFNAME_MAX_SIZE],
    if_data: usize,
}

#[repr(C)]
struct GStats {
    cmd: u32,
    len: u32,
    data: [u8; MAX_GSTRINGS * ETH_GSTRING_LEN],
}

fn gstats(sock_fd: i32, if_name: &str) -> GStats {
    let mut gstats = GStats {
        cmd: ETHTOOL_GSTATS,
        data: [0u8; MAX_GSTRINGS * ETH_GSTRING_LEN],
    };

    let mut ifname = [0u8; IFNAME_MAX_SIZE];
    ifname
        .get_mut(..if_name.len())
        .unwrap()
        .copy_from_slice(if_name.as_bytes());
    let mut ifr = IfReq {
        if_name: [0; IFNAME_MAX_SIZE],
        if_data: &&mut gstats as *mut GStats as usize,
    };

    libc::ioctl(sock_fd, libc::SIOCETHTOOL, &mut ifr);

    gstats
}
```

I have skipped error handling and a few other details on purpose. While the above works, it has a lot of issues. I raised a [PR](https://github.com/facebookincubator/below/pull/8204) to add the feature to `below` and it was merged after a few iterations. One crucial feedback was I was unnecessarily writing to out parameters before passing down to kernel. This is obviously unnecessary in hindsight and potentially a source for some UB. Second, I was asked to use [bindgen](https://github.com/rust-lang/rust-bindgen) to generate bindings for [`uapi/linux/ethtool.h`](https://github.com/torvalds/linux/blob/master/include/uapi/linux/ethtool.h) instead of redefining the types. This introduced a few issues of its own. For instance, the generated type for the above was something like this:

```rust
#[repr(C)]
pub struct ethtool_stats {
    pub cmd: __u32,
    pub n_stats: __u32,
    pub data: __IncompleteArrayField<__u64>,
}
```

Now I wasn't able to figure out how to initialize data. I wanted to fill it with zeros (or allocate some space) and pass it down to the kernel for it to be populated with the required values. I reached out to the Rust community for some help and this led to a great [discussion](https://users.rust-lang.org/t/issue-with-parsing-data-in-incompletearray-generated-by-bindgen/99851). Basically, it's not so straightforward to initialize such a type and requires a lot of pointer tricks. Some of the key points that were called out by a community member were:

- Constructing the type field-by-field does not take into account the padding that the compiler may add between fields.
- Allocating zeros is unnecessary when it could be lazily initialized or one could use [`ptr::write_bytes`](https://doc.rust-lang.org/stable/std/ptr/fn.write_bytes.html) to write zeros to the allocated memory.
- Extra care needs to be taken with the size of the type when dropping or destructing.

The entire discussion is worth a read and the whole process was a great learning experience for me. I ended up using the `ioctl(2)` approach and it worked well for my use case. However, I was still curious about how to use Netlink in Rust and if I could contribute in any way to the existing libraries. Well, as luck would have it, I had to use Netlink again for another use case. But that's a story for another post.
