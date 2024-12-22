% Manging Dotfile via Nix
% 2024-12-21

I recently learnt about Nix and how it helps develop deterministic and reproducible environments. According to its [website](https://nixos.org/), Nix is a tool for reproducible, declarative, and reliable builds. However, in this post, I will focus on how I have been using Nix to manage my dotfiles.

# Dotfiles
[Dotfiles](https://dotfiles.github.io/) are the configuration files that are used to personalize your system. These include files like `.bashrc`, `.vimrc`, `.tmux.conf`, etc. Developers often like when their terminal looks and behaves in a certain way no matter which system they are on. This is where dotfiles come in handy. Traditionally, developers would keep these files in a git repository and symlink them to the home directory. This way, they can easily share their configurations across different systems. [Dotbot](https://github.com/anishathalye/dotbot) is a popular tool that helps automate the process of managing dotfiles and which has served me well for a long time.

# Nix
In this blog, when I mention Nix, I am referring to the Nix package manager and not NixOS, which is a Linux distribution built on top of the Nix package manager. Nix is a package manager designed to make software installation and management on your computer easier, more reliable, and reproducible. Without going into too much detail, Nix allows you to define your environment in a declarative way. This means you can specify the exact versions of the packages you want to use and Nix will ensure that you get the same environment every time you build it. In short, Nix is a great tool for managing your development environment especially for developers who prefer to have their terminals having the same look and feel across different systems.

# Nix on Linux

## Installation

On Linux, you can install Nix by running the following command:

```sh
sh <(curl -L https://nixos.org/nix/install) --daemon
```

Verify the installation by running:

```sh
nix --version
```

## Home Manager

The NixOS wiki describes [Home Manager](https://nixos.wiki/wiki/Home_Manager) as a system for managing a user environment using the Nix package manager. In other words, Home Manager lets you

- install software declaratively in your user profile, rather than using nix-env
- manage dotfiles in the home directory of your user.

We are interested in the latter feature. Let's see how we can use Home Manager to manage our dotfiles.

```sh
# Create a nix folder in your configuration directory
mkdir -p ~/.config/nix
cd ~/.config/nix
mkdir -p home-manager/apps
```

## Configuration

### flake.nix

If you need to really learn about Nix language, [Nix Pills](https://nixos.org/guides/nix-pills/) covers most of the basics. But even I have not delved too deep into it but have been able to scrape by with the help of several YouTube videos and blog posts. The following has two inputs, `nixpkgs.url` which points to the Nixpkgs repository where the packages are downloaded from and the other one is `home-manager`. We'll define `home-manager` config separately in a `home.nix` file.


```nix
{
  description = "Linux system flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    nixpkgs,
    home-manager,
    ...
  }: let
    # system = "aarch64-linux"; If you are running on ARM powered computer
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    homeConfigurations = {
      <username> = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ./home-manager/home.nix
        ];
      };
    };
  };
}
```

### home.nix

Create a `home.nix` file in `nix/home-manager` directory. This file will contain the configuration for Home Manager. The following is a simple example of how you can manage your dotfiles using Home Manager. This configuration installs `neofetch` package.

```nix
{ config, pkgs, ... }:

{
  home.username = "<username>";
  home.homeDirectory = "/home/<username>";
  home.stateVersion = "23.05";
  home.packages = with pkgs; [
    neofetch
  ];
  programs.home-manager.enable = true;
}
```

Replace `<username>` with your username.

```sh
sed -i "s/<username>/$(whoami)/g" flake.nix
sed -i "s/<username>/$(whoami)/g" home-manager/home.nix
```

Now we'll use `nix run` to build and activate the configuration. After the first run, `home-manager` cli will be installed since we have `programs.home-manager.enable = true;` in our `home.nix` file. You can skip `<username>` if you are running as the current user.

```sh
nix run nixpkgs#home-manager -- switch --flake <flake-file-path>#<username>
```

You can alias this command in your shell configuration file to make it easier to run. Just make sure `<flake-file-path>` is fully qualified.

```sh
alias nix_rebuild="nix run nixpkgs#home-manager -- switch --flake <flake-file-path>#$(whoami)"
```

Now you can add the packages you want to install in the `home.nix` file and run `nix_rebuild` to apply the changes.

### Updates and Cleanups

The packages installed by Nix are pinned to the version pointed by the `flake.lock` file which is the latest version at the time of installation. To update the packages, you can run the following command:

```sh
nix flake update
```

For cleaning up the packages that are no longer needed, you can run:

```sh
nix store gc
```

Since you'll not be installing packages everyday, you bundle these commands into your alias.

```sh
alias nix_update="nix flake update && nix store gc"
alias nix_rebuild="nix_update && nix run nixpkgs#home-manager -- switch --flake ~/.config/nix~#$(whoami)"
```

### Managing Dotfiles

Now that we have our packages managed by Nix, we can take this a step further and manage our dotfiles using Nix. We can create a `dotfiles` directory in the `home-manager` directory and symlink the dotfiles to the home directory.

In the below example, we're storing all the dotfiles and configs in a `dotfiles` directory in the `home-manager` directory. We'll symlink the `.zshrc` and `nvim` config files to the home directory and `~/.config` directory respectively.

```nix
{ config, pkgs, ... }:

{
  # ...
  # Other default configurations
  # ...

  home.file.".zshrc" = {
    source = config.lib.file.mkOutOfStoreSymlink ./dotfiles/zshrc;
  };

  xdg.configFile = {
    "nvim" = {
      source = config.lib.file.mkOutOfStoreSymlink ./dotfiles/config/nvim;
      recursive = true;
    }
    # Add more configs here
  };
}
```

P.S.: I'd be remiss if I didn't mention this is not the true-Nix-style, often referred to as "impure". We are linking actual files in the traditional way (as we would do with other dotfile managers). If you would like to learn more about the Nix-style, I'd recommend checking out [this blog post](https://seroperson.me/2024/01/16/managing-dotfiles-with-nix/#configuring-things-in-nix-way). In general, it is recommended to use the Nix-style as it is more declarative and reproducible. With the impure way, you might run into some conflicts if you are not careful.

# Nix on macOS

TODO
