#cloud-config
merge_how:
 - name: list
   settings: [append, no_replace]
 - name: dict
   settings: [no_replace, recurse_list]

ssh_pwauth: false
preserve_hostname: false
hostname: ${hostname}
users:
  - default