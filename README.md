# HAProxySetup
--------------------------------------------------
This guide should help people setup haproxy as a load balancer for multiple proxy endpoints.

HAProxy website: http://www.haproxy.org/
HAProxy configuration documentation: http://cbonte.github.io/haproxy-dconv/1.8/configuration.html

Note that he HAProxy SHOULD be installed on the same network at the phones. Otherwise, if you use an external server, they will all share one public IP address and load balance differently (still works, just follow the notes). The RDM and Nginx servers do not need to be local.

If you want to run this on a local Mac, you can figure out the difference in settings (install with `brew install haproxy`) or install VirtualBox and load an Ubuntu VM on your Mac.

--------------------------------------------------
Install HAProxy 1.8 LTR with these commands for debian-based linux:
```
apt-get update
apt-get install haproxy=1.8.\*
```

Command reference is here: https://haproxy.debian.net/#?distribution=Ubuntu&release=bionic&version=1.8

--------------------------------------------------
**Optionally** You can install Squid to make your server into a proxy for use as a backend to only proxy the auth requests. No changes need to be made to the Squid config to work with this. Use these commands for debian-based linux:
```
apt-get update
apt-get install squid
```

--------------------------------------------------
**Optionally** You can configure squid to cache static assets to help lower your data usage with the below configuration:
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

Note that you will have to comment out the old `refresh_pattern .` line.

--------------------------------------------------
Save a backup the config file: /etc/haproxy/haproxy.cfg as haproxy.cfg.old
Remove everything in the haproxy.cfg and add the below text. Read the comments to make changes for your setup.
```
global
  external-check
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
  timeout connect 5s
  timeout client 60s
  timeout server 60s
  timeout check 60s
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
  option nolinger
  option http_proxy
  
  # Set the max connections to the frontend higher than the default 2000
  maxconn 5000

  # NAT static host names to a different backend
  # This ACL looks for the port 9001 in your backendurl when Manager sends data to RDM.
  acl port_rdm url_port 9001
  #acl host_name hdr_dom(host) -i ispoofer.com globalplusplus.com 104.31.70.46 104.31.71.46 104.25.91.97 104.25.92.97
  acl host_name hdr_dom(host) -i mesu.apple.com appldnld.apple.com
  
  # These two ACLs are used when a Squid backend as default backend is used so you can split these out to the paid proxies
  #acl auth hdr_dom(host) -i pgorelease.nianticlabs.com sso.pokemon.com
  #acl gd hdr_dom(host) -i api.ipotter.cc ipotter.cc ipotter.app 104.28.10.9 104.28.11.9
  
  # If your data usage is high, I would suggest using this ACL and the second "silent-drop" so map tiles aren't downloaded.
  #acl tiles hdr_dom(host) -i maps.nianticlabs.com

  # Only use one of these to drop traffic.
  http-request silent-drop if host_name
  #http-request silent-drop if host_name || tiles

  # This line is used to send Manager traffic to RDM instead of the external proxies.
  use_backend rdm if port_rdm
  # This line is used when a Squid proxy is setup so we can send auth and gd requests through the paid proxies.
  #use_backend proxy_out if auth || gd

  # This line is used to send all traffic not related to RDM to the proxies themselves. 
  # Comment out the proxy_out line and uncomment the squid line if you want all non-auth traffic to use the Squid proxy.
  default_backend proxy_out
  #default_backend squid

backend rdm
  # If you're setting up HAProxy on the same network, use `balance source`.
  # If you're setting up HAProxy on an externally hosted server, use `balance leastconn`.
  balance source
  #balance leastconn

  # Note that HAProxy messes up the HTTP header when sending data to RDM directly so we sent it to Nginx first.
  # We used 9002 as a port that Nginx is listening to because HAProxy would try to pass the whole address as a URI.
  # This assumes Nginx is installed on the same machine HAProxy is. If not, change the IP address to the server Nginx is installed on.
  # A server block for Nginx is explained in the below sections.
  server rdm 127.0.0.1:9002

backend squid
  balance source
  fullconn 1000

  server squid localhost:3128

backend proxy_out
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
  external-check command /home/rdmadmin/bancheck.sh

  # The `reqadd Proxy-Authorization` is only needed if your proxies require authentication
  # Replace base64EncodedAccountInfo with your base64 encoded username and password
  # Run this command to generate the base64: echo -n "username:password" | base64
  #reqadd Proxy-Authorization:\ Basic\ base64EncodedAccountInfo

  # The `check inter 20s fall 3 rise 2` setting will run the ban script every 20 seconds.
  # If an address fails 3 times, it will be taken down and the other addresses will get its traffic.
  # It will be put back into rotation if it passes the checker twice in a row.
  # Below are example proxy lines. Add them in the following format:
  #server <server2 name> <proxy IP>:<port> check inter 20s fall 3 rise 2
  server tor_prox01 192.168.0.6:9101 check inter 20s fall 3 rise 2
  server tor_prox02 192.168.0.6:9102 check inter 20s fall 3 rise 2
  server mpp_proxy01 104.140.211.135:312 check inter 20s fall 3 rise 2
  server mpp_proxy02 50.31.9.214:312 check inter 20s fall 3 rise 2
```

--------------------------------------------------
Create the bancheck.sh file to check your proxies are working with pokemon and niantic.
Run `chmod +x bancheck.sh` command to make it into an executable script.
Save it to the same location as the "external-check command" line.
```
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
VIP=$1
VPT=$2
RIP=$3
RPT=$4

cmd=`curl -I -s -A "pokemongo/1 CFNetwork/758.5.3 Darwin/15.6.0" -x ${RIP}:${RPT} https://pgorelease.nianticlabs.com/plfe/version 2>/dev/null | grep -e "HTTP/2 200" -e "HTTP/1.1 200 OK" && 
curl -I -s -A "pokemongo/1 CFNetwork/758.5.3 Darwin/15.6.0" -x ${RIP}:${RPT} https://sso.pokemon.com/sso/login 2>/dev/null | grep -e "HTTP/2 200" -e "HTTP/1.1 200 OK"`
exit ${?}
```

Note that this script must exit with `0` for the check to pass. You can test this script manually by running the following commands:

- `RIP=ProxyIPAddress` #This sets the RIP environment variable to the proxy IP address. You can use the HAProxy address.
- `RTP=ProxyPort` #This sets the RTP environment variable to the proxy IP port. You can use the HAProxy port.
- `./banncheck.sh` #This runs the script.
- `echo $?` #This displays the results of the script. It will most likely be 0 or 1. 

--------------------------------------------------
Edit the Ngixn config file: /etc/nginx/conf.d/default.conf. 
Add a server block for HAProxy to pass data to RDM with the correct URI. I turned the logs off because they fill fast.
If Nginx is on a different server than HAProxy, update the server_name address.
If Nginx is on a different server than RDM, update the proxy_pass address.
```
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
	
--------------------------------------------------
Test nginx and restart it. Restart HAProxy too and then check the status for any errors. Logs should also be sent to /var/log/ if needed.
```
sudo nginx -t
sudo service nginx restart
sudo service haproxy restart
sudo service haproxy status
```

--------------------------------------------------
Test the setup with curl. The first one should show "The file / was not found." because you reached RDM's data port.
The second one should show "HTTP/1.1 200 Connection established" and some other junk.
Relace the IP address with the host address of HAProxy.
```
curl -x 192.168.0.6:9100 http://192.168.0.6:9001/
curl -I -x 192.168.0.6:9100 https://sso.pokemon.com/sso/login
```

--------------------------------------------------
View the stats page to see that data went through all ends here: http://192.168.0.6:9100/haproxy?stats.
You should have a "proxy_in" as the frontend section, "rdm" as a backend, and "proxy_out" another backend.
All data should flow through the frontend. Then connections should show up for each curl you issue and go to the correct backend.
In "proxy_out", the "chk" column near the end is how many checks your proxies fail against the script.

--------------------------------------------------
I suggest testing this on one phone to ensure it is working correctly before switch all devices.
Update the phones' proxy settings to use HAProxy. 
- Settings > Wifi > SSID > Proxy > Manual > Enter your information.

You may also want to set a public DNS since addresses have resolution problems. 
- Settings > Wifi > SSID > DNS
- Google's DNSs are 8.8.8.8 and 8.8.4.4, either will work.

In RDM UIC Manager, ensure your backend URL uses the IP address and port 9001 of the HAProxy server.
Check that the phone's data makes it to the map and you should be done.

--------------------------------------------------
