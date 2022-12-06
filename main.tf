# variables that can be overriden
variable "hostname" {
  type    = list(string)
  default = ["dev1.kras", "dev2.kras"]
}
variable "domain" { default = "local" }
variable "memoryMB" { default = 1024 * 2 }
variable "cpu" { default = 2 }

terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}




# instance the provider
provider "libvirt" {
  uri = "qemu:///system"
}
#fetch the latest ubuntu release image from their mirrors.
#when ising cloud image- now allowed to increase disk-size
#only on localy downloaded image with command:
#qemu-img resize images/focal-server-cloudimg-amd64-disk-kvm.img 10G
resource "libvirt_volume" "os_image" {
  count = length(var.hostname)
  name  = "os_image.${var.hostname[count.index]}"
  pool  = "default"
  #source = "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64-disk-kvm.img"
  #source = "https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2"
  #source = "images/focal-server-cloudimg-amd64-disk-kvm.img" #
  #source = "http://localhost:8000/focal-server-cloudimg-amd64-disk-kvm.img" #
  source = "http://localhost:8000/focal-server-cloudimg-amd64.img"
  format = "qcow2"
}
# Use CloudInit ISO to add ssh-key to the instance
resource "libvirt_cloudinit_disk" "commoninit" {
  count = length(var.hostname)
  name  = "${var.hostname[count.index]}-commoninit.iso"
  #name = "${var.hostname}-commoninit.iso"
  # pool = "default"
  user_data      = data.template_file.user_data[count.index].rendered
  network_config = data.template_file.network_config.rendered
}
data "template_file" "user_data" {
  count    = length(var.hostname)
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    hostname = element(var.hostname, count.index)
    fqdn     = "${var.hostname[count.index]}.${var.domain}"
  }
}
data "template_file" "network_config" {
  template = file("${path.module}/network_config_dhcp.cfg")

}
# Create the machine
resource "libvirt_domain" "domain-ubuntu" {
  count  = length(var.hostname)
  name   = var.hostname[count.index]
  memory = var.memoryMB
  vcpu   = var.cpu
  disk {
    volume_id = element(libvirt_volume.os_image.*.id, count.index)
  }
  network_interface {
    network_name = "default"
  }
  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id
  # IMPORTANT
  # Ubuntu can hang is a isa-serial is not present at boot time.
  # If you find your CPU 100% and never is available this is why
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = "true"
  }
}
terraform {
  required_version = ">= 0.12"
}
output "ips" {
  # show IP, run 'terraform refresh' if not populated
  value = libvirt_domain.domain-ubuntu.*.network_interface.0.addresses
}



# resource "local_file" "ansible_inventory" {
#   content = templatefile("inventory.tmpl",
#     {
#      ansible_group_shards = google_compute_instance.shard.*.labels.ansible-group,
#      ansible_group_index = google_compute_instance.shard.*.labels.ansible-index,
#      hostname_shards = google_compute_instance.shard.*.name,
#      ansible_group_cfg = google_compute_instance.cfg.*.labels.ansible-group,
#      hostname_cfg = google_compute_instance.cfg.*.name,
#      ansible_group_mongos = google_compute_instance.mongos.*.labels.ansible-group,
#      hostname_mongos = google_compute_instance.mongos.*.name,
#      number_of_shards = range(var.shard_count)
#     }
#   )
#   filename = "inventory"
# }


resource "null_resource" "localinventorynull01" {

  triggers = {
    mytest = timestamp()
  }

  provisioner "local-exec" {

    command = "echo ${libvirt_domain.domain-ubuntu[0].name} ansible_host=${element(libvirt_domain.domain-ubuntu[0].network_interface[0].addresses, 0)} ansible_user=ec2-user ansible_ssh_private_key_file=/root/xyz.pem>> inventory"

  }


  depends_on = [
    libvirt_domain.domain-ubuntu
  ]

}

# resource "null_resource" "localinventorynull02" {
# 	triggers = {
# 		mytest = timestamp()
# 	}

# 	provisioner "local-exec" {
# 	    command = "echo ${aws_instance.os2.tags.Name} ansible_host=${aws_instance.os2.public_ip} ansible_user=ec2-user ansible_ssh_private_key_file=/root/terra_may.pem>> inventory"

# 	  }

#          depends_on = [ 
# 			null_resource.localinventorynull01 
# 			]
# }
