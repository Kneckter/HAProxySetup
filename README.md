# HAProxy Setup for Mapping

This guide will assist you in setting up HAProxy as a load balancer for multiple proxy endpoints. 
## Notes and Warnings

HAProxy doesn't work with paid proxies that are Socks5 or SSL, at least not if they require authentication. I never tried SOCKS or SSL paid proxies that don't require authentication. 

## Reference Documentation

- [HAProxy](http://www.haproxy.org/)
- [HAProxy Configuration Documentation](http://cbonte.github.io/haproxy-dconv/2.6/configuration.html)

Please note that HAProxy should ideally be installed on the same network as the MITM clients. If you're using an external server, they will all share one public IP address and load balance differently. However, it will still work, just follow the notes. The RDM and Nginx servers do not need to be local.

## Installation

### HAProxy

To install HAProxy 2.6 LTS on Debian 11, follow these steps:

1. Enable a dedicated repository:
    ```bash
    curl https://haproxy.debian.net/bernat.debian.org.gpg | gpg --dearmor > /usr/share/keyrings/haproxy.debian.net.gpg
    echo deb "[signed-by=/usr/share/keyrings/haproxy.debian.net.gpg]" http://haproxy.debian.net bullseye-backports-2.6 main > /etc/apt/sources.list.d/haproxy.list
    ```
2. Update your package lists and install HAProxy:
    ```bash
    apt update
    apt install haproxy=2.6.\*
    ```
You will get the _latest_ release of HAProxy 2.6 (and stick to this branch).

Command reference is here: [HAProxy Debian](https://haproxy.debian.net/#distribution=Debian&release=bullseye&version=2.6)

For other Debian or Ubuntu releases, you can find all commands here: [HAProxy Debian](https://haproxy.debian.net/)

### Squid

To install Squid on Debian-based Linux distributions, use the following commands:

```bash
apt update
apt install squid
```

### Banchecker scripts
Next, create `bancheck_ptc.sh` and `bancheck_nia.sh` files using the command 
```
`touch bancheck_ptc.sh && touch bancheck_nia.sh`
```
These files will help check if your proxies are working with Pokemon and Niantic. 

Make these files executable by running the command 
```
`chmod +x bancheck_ptc.sh && chmod +x bancheck_nia.sh`
```

Ensure these files are saved in the same location as specified in the "external-check command" line of haproxy.conf. 

If your proxy uses a username/password instead of an IP whitelist, you will need to add `-U username:password` before the `-x` flag. 

Add this to the `bancheck_ptc.sh` file:
```
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
VIP=$1
VPT=$2
RIP=$3
RPT=$4

cmd=`curl -I -s -A "pokemongo/1 CFNetwork/758.5.3 Darwin/15.6.0" -x ${RIP}:${RPT} https://sso.pokemon.com/sso/login 2>/dev/null | grep -e "HTTP/2 200" -e "HTTP/1.1 200 OK"`
exit ${?}
```

Add this to the `bancheck_nia.sh` file:
```
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
VIP=$1
VPT=$2
RIP=$3
RPT=$4

cmd=`curl -I -s -A "pokemongo/1 CFNetwork/758.5.3 Darwin/15.6.0" -x ${RIP}:${RPT} https://pgorelease.nianticlabs.com/plfe/version 2>/dev/null | grep -e "HTTP/2 200" -e "HTTP/1.1 200 OK"`
exit ${?}
```

## Configurations
### Squid Configuration (optional)

Configure Squid to cache static assets, which can help reduce your data usage.
Find and Comment out the existing `refresh_pattern .` line.
Add the following configuration to `/etc/squid/squid.conf`:

```
maximum_object_size 200 MB
cache_dir ufs /var/spool/squid 4096 16 256
logfile_rotate 5
cache_store_log daemon:/var/log/squid/store.log
refresh_pattern -i \.(gif|png|jpg|jpeg|ico|bmp|obj)$ 10080 90% 43200 override-expire ignore-no-cache ignore-no-store ignore-private
refresh_pattern -i \.(iso|avi|mov|wav|qt|mpg|mp3|mp4|mpeg|swf|flv|x-flv|wmv|au|mid|gmm)$ 43200 90% 432000 override-expire ignore-no-cache ignore-no-store ignore-private
refresh_pattern -i \.(deb|rpm|exe|zip|tar|gz|tgz|ram|rar|bin|ppt|doc|tiff|tif|arj|lha|lzh|hqx|pdf|rtf)$ 10080 90% 43200 override-expire ignore-no-cache ignore-no-store ignore-private
refresh_pattern -i \.index.(html|htm)$ 0 40% 10080
refresh_pattern -i \.(html|htm|css|js|jsp|txt|xml|tsv|json)$ 1440 40% 40320
refresh_pattern . 0 40% 40320
```

---
### HAProxy Configuration
Before proceeding, ensure you create a backup of the config file: `/etc/haproxy/haproxy.cfg` and save it as `haproxy.cfg.old`. 
Clear everything in `haproxy.cfg` and insert the text provided below. 
Make sure to read the comments to customize the setup for your needs:

```
global
  external-check
  insecure-fork-wanted				  
  log /dev/log local1 notice

  # Default SSL material locations
  ca-base /etc/ssl/certs
  crt-base /etc/ssl/private

  # Default ciphers to use on SSL-enabled listening sockets.
  # For more information, see ciphers(1SSL). This list is from:
  #  https://hynek.me/articles/hardening-your-web-servers-ssl-ciphers/
  # An alternative list with additional directives can be obtained from
  #  https://mozilla.github.io/server-side-tls/ssl-config-generator/?server=haproxy
  ssl-default-bind-ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:RSA+AESGCM:RSA+AES:!aNULL:!MD5:!DSS
  ssl-default-bind-options no-sslv3

defaults
  log global
  mode http
  option httplog
  option dontlognull
  option forwardfor
  timeout connect 5000ms
  timeout client 50000ms
  timeout server 50000ms
  timeout check 90s
  errorfile 400 /etc/haproxy/errors/400.http
  errorfile 403 /etc/haproxy/errors/403.http
  errorfile 408 /etc/haproxy/errors/408.http
  errorfile 500 /etc/haproxy/errors/500.http
  errorfile 502 /etc/haproxy/errors/502.http
  errorfile 503 /etc/haproxy/errors/503.http
  errorfile 504 /etc/haproxy/errors/504.http

frontend proxy_in
  bind *:9100
  # The stats page is not required but it should be used during the initial setup so you know it works.
  stats uri /haproxy?stats
  mode http
  option http-use-proxy-header
  option accept-invalid-http-request

 # Set the max connections to the frontend higher than the default 2000
  maxconn 5000

  # These two ACLs are used to split game traffic to the paid proxies
  acl ptc_auth hdr_dom(host) -i sso.pokemon.com
  acl pgorelease hdr_dom(host) -i pgorelease.nianticlabs.com

 # NAT static host names to a different backend
 # This ACL looks for the port 9001 in your backendurl when Manager sends data to RDM.
  acl port_rdm url_port 9001

  # These two ACLs are used to drop traffic. The one that's enabled should stop iOS updates
  #acl host_name hdr_dom(host) -i ispoofer.com globalplusplus.com 104.31.70.46 104.31.71.46 104.25.91.97 104.25.92.97
  acl host_name hdr_dom(host) -i mesu.apple.com appldnld.apple.com apple.com

  # These two ACLs are used when a Squid backend as default backend is used so you can split these out to the paid proxies
  #acl auth hdr_dom(host) -i pgorelease.nianticlabs.com sso.pokemon.com
  #acl gd hdr_dom(host) -i api.ipotter.cc ipotter.cc ipotter.app 104.28.10.9 104.28.11.9

  # If your data usage is high, I would suggest using this ACL and the second "silent-drop" so map tiles aren't downloaded.
  #acl tiles hdr_dom(host) -i maps.nianticlabs.com

  # Only use one of these to drop traffic.
  http-request deny if host_name
  #http-request deny if host_name || tiles

  # These are used to split the traffic on the paid proxies
  use_backend proxy_ptc if ptc_auth
  use_backend proxy_nia if pgorelease

  # This line is used to send Manager traffic to RDM instead of the external proxies.
  use_backend rdm if port_rdm

  # This line is used when a Squid proxy is setup so we can send auth and gd requests through the paid proxies.
  #use_backend proxy_out if auth || gd

  # This line is used to send all traffic not related to RDM or the game to the Squid proxy on the intranet.
  default_backend squid

backend rdm
  # If you're setting up HAProxy on the same network, use `balance source`.
  # If you're setting up HAProxy on an externally hosted server, use `balance leastconn`.
  balance source
  #balance leastconn					
  fullconn 1000

  # Note that HAProxy messes up the HTTP header when sending data to RDM directly so we sent it to Nginx first.
  # We used 9002 as a port that Nginx is listening to because HAProxy would try to pass the whole address as a URI.
  # This assumes Nginx is installed on the same machine HAProxy is. If not, change the IP address to the server Nginx is installed on.
  # A server block for Nginx is explained in the below sections.
  server rdm 192.168.1.171:9002

backend squid
  balance source
  fullconn 10000
  mode http
  server squid localhost:3128

backend proxy_ptc
  # If you're setting up HAProxy on the same network, use `balance source`.
  # If you're setting up HAProxy on an externally hosted server, use `balance leastconn`.
  balance source
  #balance leastconn					

  # Set the max connections for each server to 1000 so you don't drop data
  # This defauls to 10% of maxconn or 10% of the default (which limits it to 200 connections)
  fullconn 1000

  # This section of external-check settings is important for checking if your proxy IP is banned.
  option external-check
  external-check path "/usr/bin:/bin"

  # The `external-check command` is used with the location of the file created in the next section.
  external-check command /home/tstuart/bancheck_ptc.sh

  # The `reqadd Proxy-Authorization` is only needed if your proxies require authentication
  # Replace base64EncodedAccountInfo with your base64 encoded username and password
  # Run this command to generate the base64: echo -n "username:password" | base64

  # The `check inter 20s fall 3 rise 2` setting will run the ban script every 20 seconds.
  # If an address fails 3 times, it will be taken down and the other addresses will get its traffic.
  # It will be put back into rotation if it passes the checker twice in a row.
  # Below are example proxy lines. Add them in the following format:
    server proxy1 193.38.242.179:8800 check inter 20s fall 3 rise 2
    server proxy2 193.38.242.32:8800 check inter 20s fall 3 rise 2
    server proxy3 196.51.90.88:8800 check inter 20s fall 3 rise 2
    server proxy4 196.51.69.253:8800 check inter 20s fall 3 rise 2
    server proxy5 196.51.69.55:8800 check inter 20s fall 3 rise 2

backend proxy_nia
  # If you're setting up HAProxy on the same network, use `balance source`.
  # If you're setting up HAProxy on an externally hosted server, use `balance leastconn`.
  balance source
  #balance leastconn

  # Set the max connections for each server to 1000 so you don't drop data
  # This defauls to 10% of maxconn or 10% of the default (which limits it to 200 connections)
  fullconn 1000

  # This section of external-check settings is important for checking if your proxy IP is banned.
  option external-check
  external-check path "/usr/bin:/bin"

  # The `external-check command` is used with the location of the file created in the next section.
  external-check command /home/tstuart/bancheck_nia.sh

  # The `reqadd Proxy-Authorization` is only needed if your proxies require authentication
  # Replace base64EncodedAccountInfo with your base64 encoded username and password
  # Run this command to generate the base64: echo -n "username:password" | base64

  # The `check inter 20s fall 3 rise 2` setting will run the ban script every 20 seconds.
  # If an address fails 3 times, it will be taken down and the other addresses will get its traffic.
  # It will be put back into rotation if it passes the checker twice in a row.
  # Below are example proxy lines. Add them in the following format:
    server proxy1 196.51.69.54:8800 check inter 20s fall 3 rise 2
    server proxy2 196.51.69.94:8800 check inter 20s fall 3 rise 2
    server proxy3 192.126.135.49:8800 check inter 20s fall 3 rise 2
    server proxy4 196.51.90.202:8800 check inter 20s fall 3 rise 2
    server proxy5 192.126.135.196:8800 check inter 20s fall 3 rise 2
```
### Nginx Configuration

Add a server block for HAProxy to pass data to RDM with the correct URI. 
Logs have been turned off to prevent them from filling up quickly. 
If Nginx is on a different server than HAProxy, update the `server_name` address. 
If Nginx is on a different server than RDM, update the `proxy_pass` address. 
If this setup is on a server with just HAProxy and Nginx, the file to update is `/etc/nginx/sites-available/default`
If an existing Nginx is being used, adjust accordingly.

```nginx
server {
  listen 9002;
  server_name  127.0.0.1;

  location / {
    proxy_pass http://127.0.0.1:9001;
    access_log off;
    error_log /dev/null;
  }
}
```

If you use Apache as your web service, here's an example of the above configuration:

```apache
<VirtualHost haproxy.domain.com:80>
  KeepAlive On
  ServerName 127.0.0.1
  ProxyPreserveHost On
  ProxyPass / http://127.0.0.1:9001/
  ProxyPassReverse / http://127.0.0.1:9001/
  
  ErrorLog ${APACHE_LOG_DIR}/error.log
</VirtualHost>
```

---

Test Nginx and restart it. Restart HAProxy as well and then check the status for any errors. Logs are sent to `/var/log/` if needed.

```bash
sudo nginx -t
sudo service nginx restart
sudo service haproxy restart
sudo service haproxy status
```
---
# Troubleshooting
## Banchecker Tests
These scripts must exit with `0` for the check to pass. 
You can test these scripts manually by running the following commands in order:
- `RIP=ProxyIPAddress` #This sets the RIP environment variable to the proxy IP address. Use the HAProxy address.
- `RTP=ProxyPort` #This sets the RTP environment variable to the proxy IP port. Use the HAProxy port.
- `./banncheck_ptc.sh` or `./bancheck_nia.sh`  #This runs the script.
- `echo $?` #This displays the results of the script. It will most likely be 0 or 1.
  
## Proxy tests
Test the setup with curl. 
The first command should show "The file / was not found." because you reached RDM's data port. The second and third commands should show "HTTP/1.1 200 Connection established" and some other information.

Replace the IP address with the host address of HAProxy.

```bash
curl -x 192.168.1.171:9100 http://192.168.0.6:9001/
curl -I -x 192.168.1.171:9100 https://sso.pokemon.com/sso/login
curl -I -x 192.168.1.171:9100 https://google.com
```

---

View the stats page at `http://192.168.1.171:9100/haproxy?stats` to see that data went through all ends here.

---

Before switching all devices, I suggest testing this on one device to ensure it is working correctly.

Update the device proxy settings to use HAProxy:
- iOS: Settings > Wifi > SSID > Proxy > Manual > Enter your information.
- Android ADB: `adb shell settings put global http_proxy 192.168.1.171:9100` (Replace IP and Port with your information)

If you have resolution problems with public addresses, you may want to set a public DNS such as Google DNS (8.8.8.8 and 8.8.4.4), Cloudflare (1.1.1.1 and 1.0.0.1), or any other public DNS.
- iOS: Settings > Wifi > SSID > DNS
- Android ADB: `adb shell setprop net.eth0.dns1 8.8.8.` and `adb shell setprop net.eth0.dns2 4.`

In the MITM config, ensure your backend URL uses the IP address and port 9001 of the HAProxy server.

Check that the phone's or ATV data makes it to the map and you should be done.
