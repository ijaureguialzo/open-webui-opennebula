resource "opennebula_virtual_machine" "master" {

  template_id = data.opennebula_template.template.id

  name = local.opennebula.vm.name

  cpu    = local.opennebula.limits.cpu
  vcpu   = local.opennebula.limits.vcpu
  memory = local.opennebula.limits.memory

  lock = local.opennebula.vm.locked ? "USE" : "UNLOCK"

  context = {
    NETWORK        = "YES"
    SET_HOSTNAME   = "$NAME"
    SSH_PUBLIC_KEY = join("\n", [
      join("\n", split("|", replace(var.SSH_PUBLIC_KEY, "/[\"']/", ""))),
      file("~/.ssh/id_rsa.pub")
    ])
  }

  group = local.opennebula.connection.group

  nic {
    model      = "virtio"
    network_id = data.opennebula_virtual_network.network.id
  }

  disk {
    image_id = data.opennebula_template.template.disk[0].image_id
    target   = "vda"
    size     = local.opennebula.limits.disk
  }
}

resource "null_resource" "ansible_master" {
  depends_on = [
    opennebula_virtual_machine.master
  ]

  provisioner "local-exec" {
    quiet   = true
    command = <<EOT
      ANSIBLE_HOST_KEY_CHECKING=False \
      ANSIBLE_FORCE_COLOR=True \
      ansible-playbook \
        -i "${local.master.connection_ip}," \
        /ansible/master-playbook.yml
    EOT
  }
}

resource "null_resource" "ansible_portainer" {
  depends_on = [
    null_resource.ansible_master
  ]

  count = local.ansible.install_portainer ? 1 : 0

  provisioner "local-exec" {
    quiet   = true
    command = <<EOT
      ANSIBLE_HOST_KEY_CHECKING=False \
      ANSIBLE_FORCE_COLOR=True \
      ansible-playbook \
        -i "${local.master.connection_ip}," \
        /ansible/portainer-playbook.yml
    EOT
  }
}

locals {
  master = {
    name          = opennebula_virtual_machine.master.name
    private_ip    = opennebula_virtual_machine.master.nic[0].computed_ip
    public_ip     = lookup(local.ip_publica, opennebula_virtual_machine.master.nic[0].computed_ip, "")
    connection_ip = local.ansible.connect_to_public_ip ? lookup(local.ip_publica, opennebula_virtual_machine.master.nic[0].computed_ip, "") : opennebula_virtual_machine.master.nic[0].computed_ip
  }
}

output "master" {
  value = local.master
}

output "portainer_url" {
  value = local.ansible.install_portainer ? format("https://%s:9443",local.master.connection_ip) : ""
}

output "open_webui_url" {
  value = format("https://%s.%s", local.cloudflare.subdomain, local.cloudflare.domain)
}
