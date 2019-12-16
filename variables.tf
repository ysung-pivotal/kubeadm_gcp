variable "master_machine_type" {
  type          = string
  default       = "n1-standard-2"
}

variable "gcp_project" {
  type		= string
  default	= "pde-ysung"
}

variable "worker_machine_type" {
  type          = string
  default       = "n1-standard-2"
}

variable "master_count" {
  type          = number
  default       = 1
}

variable "worker_count" {
  type          = number
  default       = 3
}

variable "k8s_version" {
  type		= string
  default	= "1.17.0"
}

variable "k8s_service_dns" {
  type		= string
  default	= "k8s.ysung.tips"
}

variable "subnet_cidr" {
  type          = string
  default       = "192.168.0.0/24"
}

variable "k8s_pod_cidr" {
  type          = string
  default       = "10.200.0.0/16"
}

variable "k8s_service_cidr" {
  type		= string
  default	= "10.96.0.0/12"
}

variable "user" {
  type		= string
  default	= "ysung"
}
