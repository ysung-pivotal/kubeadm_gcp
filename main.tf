provider "google" {
  credentials	= "${file("/Users/ysung/pde-ysung.json")}"
  project	= "pde-ysung"
  region	= "us-central1"
  zone		= "us-central1-a"
}

data "google_compute_image" "kubeadm_gce_image" {
  family 	= "ubuntu-1804-lts"
  project 	= "ubuntu-os-cloud"
}

resource "google_compute_network" "vpc" {
  name 		= "k8s-vpc"
  auto_create_subnetworks	= false

  provisioner "local-exec" {
    when 	= "destroy"
    command = "gcloud compute routes list --filter=\"name~'kubernetes*'\" --uri | xargs gcloud compute routes delete --quiet"
  }

  provisioner "local-exec" {
    when	= "destroy"
    command = "gcloud compute firewall-rules list --filter=\"name~'k8s*'\" --uri | xargs gcloud compute firewall-rules delete --quiet"
  }
}

resource "google_compute_subnetwork" "subnet" {
  name		= "k8s-subnet"
  ip_cidr_range	= var.subnet_cidr
  network	= "${google_compute_network.vpc.self_link}"
}

resource "google_compute_firewall" "k8s-firewall-internal" {
  name		= "k8s-allow-internal"
  network	= "${google_compute_network.vpc.self_link}"
  allow	{
	protocol = "tcp"
  }
  allow {
	protocol = "udp"
  }
  allow {
	protocol = "icmp"
  }
  source_ranges = [var.subnet_cidr,var.k8s_pod_cidr]
}

resource "google_compute_firewall" "k8s-firewall-external" {
  name		= "k8s-allow-external"
  network	= "${google_compute_network.vpc.self_link}"
  allow {
	protocol = "tcp"
	ports = ["22", "6443"]
  }
  allow {
	protocol = "icmp"
  }
  source_ranges	= ["0.0.0.0/0"]
}
/*
resource "google_compute_firewall" "k8s-firewall-lb-probe" {
  name		= "k8s-allow-lb-probe"
  network	= "${google_compute_network.vpc.self_link}"
  allow {
	protocol = "tcp"
  }
  source_ranges	= ["35.191.0.0/16","209.85.152.0/22", "209.85.204.0/22"]
}
*/
resource "google_compute_address" "lb_ext_ip" {
  name	= "lb-ext-ip"
}

resource "google_dns_record_set" "k8s_lbs" {
  name = "api.k8s.ysung.tips."
  type = "A"
  ttl	= 300
  managed_zone = "ysung-tips"
  rrdatas = ["${google_compute_address.lb_ext_ip.address}"]
}
/*
resource "google_compute_http_health_check" "k8s_api_health_check" {
  name	= "k8s-api-health-check"
  host	= "kubernetes.default.svc.k8s.ysung.tips"
  request_path = "/healthz"
}

resource "google_compute_target_pool" "k8s_api_target_pool" {
  name = "k8s-api-target-pool"
  instances = "${google_compute_instance.k8s-master[*].self_link}"
  health_checks = ["${google_compute_http_health_check.k8s_api_health_check.name}"]
}

resource "google_compute_forwarding_rule" "k8s-api-lb-forwarding" {
  name	= "k8s-api-lb-forwarding"
  target	= "${google_compute_target_pool.k8s_api_target_pool.self_link}"
  ip_address	= "${google_compute_address.lb_ext_ip.address}"
  port_range	= "6443"
}
*/
resource "google_compute_instance" "k8s-master" {
  count = var.master_count 
  name		= "k8s-master${count.index + 1}"
  machine_type	= var.master_machine_type
  metadata	= {
    ssh-keys = "ysung: ${file("~/.ssh/id_rsa.pub")}"
  }
  boot_disk {
    auto_delete		= true
    initialize_params {
      size	= 200
      image	= "${data.google_compute_image.kubeadm_gce_image.self_link}"
    }
  }
  network_interface {
    subnetwork	= "${google_compute_subnetwork.subnet.self_link}"
    network_ip	= cidrhost(var.subnet_cidr, count.index+11)
    access_config {
      nat_ip = "${google_compute_address.lb_ext_ip.address}"
    }
  }
  can_ip_forward	= true
  tags		= ["kubernetes", "k8s", "controller"]
  service_account {
    scopes = ["compute-rw","storage-ro","service-management","service-control","logging-write","monitoring"]
  }
}

resource "google_compute_instance" "k8s-workers" {
  count		= var.worker_count
  name		= "k8s-worker${count.index+1}"
  machine_type	= var.worker_machine_type
  metadata	= {
    ssh-keys = "ysung: ${file("~/.ssh/id_rsa.pub")}"
    pod-cidr	= cidrsubnet(var.k8s_pod_cidr,16,count.index+1)
  }
  boot_disk {
    auto_delete		= true
    initialize_params {
      size	= 200
      image	= "${data.google_compute_image.kubeadm_gce_image.self_link}"
    }
  }
  network_interface {
    subnetwork	= "${google_compute_subnetwork.subnet.self_link}"
    network_ip	= cidrhost(var.subnet_cidr,count.index+21)
    access_config {
    }
  }
  can_ip_forward	= true
  tags		= ["kubernetes", "k8s", "worker"]
  service_account {
    scopes = ["compute-rw","storage-ro","service-management","service-control","logging-write","monitoring"]
  }
  
}
/*
resource "google_compute_route" "k8s-pod-routes" {
  count 	= var.worker_count
  name		= "k8s-pod-route${count.index+1}"
  network	= "${google_compute_network.vpc.self_link}"
  dest_range	= cidrsubnet(var.k8s_pod_cidr,16,count.index+1)
  next_hop_instance	= "${element(google_compute_instance.k8s-workers.*.self_link, count.index)}"
}
*/
data "template_file" "k8s-ansible-inventory" {
  template = "${file("./templates/hosts.tpl")}"
  depends_on = [ "google_compute_instance.k8s-master", "google_compute_instance.k8s-workers" ]
  vars = {
    k8s_master = "${join("\n", [for instance in google_compute_instance.k8s-master : join("", [instance.name, " ansible_host=", instance.network_interface.0.access_config.0.nat_ip])])}"
    k8s_worker = "${join("\n", [for instance in google_compute_instance.k8s-workers: join("", [instance.name, " ansible_host=", instance.network_interface.0.access_config.0.nat_ip])])}"
  }
}

resource "local_file" "hosts" {
  content = "${data.template_file.k8s-ansible-inventory.rendered}"
  filename = "./hosts"
}

data "template_file" "kubeadm_config" {
  template = "${file("./templates/kubeadm-config.tpl")}"
  vars = {
    k8s_version = var.k8s_version
    k8s_service_dns = var.k8s_service_dns
    k8s_pod_cidr = var.k8s_pod_cidr
  }
}

resource "local_file" "kubeadm_config" {
  content = "${data.template_file.kubeadm_config.rendered}"
  filename = "./kubeadm.config"
}

data "template_file" "cloud-config" {
  template = "${file("./templates/cloud-config.tpl")}"
  vars = {
     gcp_project = var.gcp_project
  }
}

resource "local_file" "cloud-config" {
  content = "${data.template_file.cloud-config.rendered}"
  filename = "./cloud-config"
}

resource "null_resource" "kubeadm" {
  depends_on = ["local_file.hosts", "local_file.kubeadm_config", "local_file.cloud-config"]
  provisioner "local-exec" {
    command = "ansible-playbook kubeadm_all.yaml"
  }
}

