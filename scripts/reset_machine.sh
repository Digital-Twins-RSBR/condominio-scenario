#!/bin/bash
set -e

echo "==== Removendo Docker, containerd, Compose, Python, Ansible, e dependências de rede ===="
sudo systemctl stop docker || true
sudo systemctl stop containerd || true

for pkg in docker docker.io docker-ce docker-ce-cli docker-compose docker-compose-plugin \
    containerd containerd.io runc podman-docker \
    ansible python3-pip python3-venv python3-dev \
    socat net-tools bridge-utils iproute2 tcpdump \
    libffi-dev libssl-dev graphviz xterm unzip; do
  sudo apt-get purge -y "$pkg" || true
done

sudo apt-get autoremove -y
sudo apt-get autoclean -y

echo "==== Removendo repositórios Docker e chaves extras ===="
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -rf /etc/apt/keyrings/docker.gpg

echo "==== Limpando listas de pacotes ===="
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update

echo "==== Removendo diretórios residuais ===="
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker /etc/containerd

echo "==== Limpeza concluída. Sistema pronto para reinstalação limpa. ===="
