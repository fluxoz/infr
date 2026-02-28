{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/virtualisation/linode-image.nix"
    "${modulesPath}/virtualisation/linode-config.nix"
  ];

  system.stateVersion = "25.11";  

  users.users.root = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICRyw8DcPB6PN/KAuFNV47vjjKc4oNSc1yemko7hObTi"
    ];
  };

  users.users.user = {
    isNormalUser = true;
    home = "/home/user";
    shell = pkgs.bash;
    extraGroups = [ "wheel" ];
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICRyw8DcPB6PN/KAuFNV47vjjKc4oNSc1yemko7hObTi"
    ];
  };

  security.sudo.wheelNeedsPassword = false;


  environment.systemPackages = with pkgs; [ 
    vim
    curl
    wget
    git
    htop
    tmux
    fail2ban
    neofetch
  ];

  services.fail2ban = lib.mkDefault {
    enable = true;
    jails = {
      sshd = {
        settings = {
          enabled = true;
          port = "ssh";
          filter = "sshd";
          backend = "systemd";
          logpath = "journal ";
          maxretry = 3;
          bantime = 3600;
          findtime = 600;
        };
      };
    };
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  swapDevices = [ 
    { device = "/dev/disk/by-label/linode-swap"; }
  ];
}
