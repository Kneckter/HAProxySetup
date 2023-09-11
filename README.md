# HAProxySetup for mapping
--------------------------------------------------
This guide should help you to setup haproxy as a load balancer for multiple proxy endpoints.

HAProxy website: http://www.haproxy.org/
HAProxy configuration documentation: http://cbonte.github.io/haproxy-dconv/2.6/configuration.html

HAProxy SHOULD be installed on the same network as the MITM clients.
Otherwise, if you use an external server, they will all share one public IP address and load balance differently (still works, just follow the notes). The RDM and Nginx servers do not need to be local.

If you want to run this on a local Mac, you can figure out the difference in settings (install with `brew install haproxy`) or install VirtualBox and load an Ubuntu VM on your Mac.
--------------------------------------------------
Notes and Warnings
HAProxy doesn't work with paid proxies that are Socks5 or SSL, at least not if they require authentication. I never tried SOCS or SSL paid proxies that don't require authentication. 
--------------------------------------------------
Install HAProxy 2.6 LTS with these commands on debian 11:

**Login as root or use sudo -i  for a root shell.**

First enable a dedicated repository:
```
curl https://haproxy.debian.net/bernat.debian.org.gpg \
      | gpg --dearmor > /usr/share/keyrings/haproxy.debian.net.gpg
 ```
 ```     
echo deb "[signed-by=/usr/share/keyrings/haproxy.debian.net.gpg]" \
      http://haproxy.debian.net bullseye-backports-2.6 main \
      > /etc/apt/sources.list.d/haproxy.list
 ```
 Then, use the following commands:
```
apt update
apt install haproxy=2.6.\*
```
You will get the _latest_ release of HAProxy 2.6 (and stick to this branch).

Command reference is here: https://haproxy.debian.net/#distribution=Debian&release=bullseye&version=2.6

For other Debian or Ubuntu release you find all commands here:
https://haproxy.debian.net/

--------------------------------------------------
Install Squid to make your server into a proxy for use as a backend to only proxy the auth requests. No changes need to be made to the Squid config to work with this. Use these commands for debian-based linux:
```
apt update
apt install squid
```
--------------------------------------------------
*Optional configuration*
Configure squid to cache static assets to help lower your data usage with the below configuration added to /etc/squid/squid.conf
```
[Squid.conf file](/squid.conf)
https://github.com/StuartMedia/HAProxySetup/blob/8593777b0857cd5c788cefe4641ec11ce445df02/squid.conf#L1-L10
```
Note that you will have to comment out the old `refresh_pattern .` line.

--------------------------------------------------
Save a backup the config file: /etc/haproxy/haproxy.cfg as haproxy.cfg.old
Remove everything in the haproxy.cfg and add the below text. Read the comments to make changes for your setup.
```
https://github.com/StuartMedia/HAProxySetup/blob/cc32ebdc9a61b8b61b676572fb0918b02c1c3c82/haproxy.cfg#L1-L158C59
```

--------------------------------------------------
Create the bancheck_ptc.sh and bancheck_nia.sh files `touch bancheck_ptc.sh && touch bancheck_nia.sh` to check your proxies are working with pokemon and niantic.
Run `chmod +x bancheck_ptc.sh && chmod +x bancheck_nia.sh` command to make it into an executable script.
Save them to the same location as the "external-check command" line.
If your proxy uses a UN/PW instead of IP whitelist, you will need to add `-U username:password` before the `-x` flag.
Add this to the bancheck_ptc.sh file:
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
Add this to the bancheck_nia.sh file:
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

Note that this script must exit with `0` for the check to pass. 
You can test this script manually by running the following commands in same order as provided:
- `RIP=ProxyIPAddress` #This sets the RIP environment variable to the proxy IP address. Use the HAProxy address.
- `RTP=ProxyPort` #This sets the RTP environment variable to the proxy IP port. Use the HAProxy port.
- `./banncheck_ptc.sh` #This runs the script.
- `echo $?` #This displays the results of the script. It will most likely be 0 or 1. 

--------------------------------------------------
Nginx config
Add a server block for HAProxy to pass data to RDM with the correct URI. I turned the logs off because they fill fast.
If Nginx is on a different server than HAProxy, update the server_name address.
If Nginx is on a different server than RDM, update the proxy_pass address.
If this setup is a server with just haproxy and nginx file to update is /etc/nginx/sites-available/default
      - If an existing nginx is being used adjust accordingly.
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
If you use Apache as your webservice, this is an example of the above config:
```
<VirtualHost haproxy.domain.com:80>
  KeepAlive On
  ServerName 127.0.0.1
  ProxyPreserveHost On
  ProxyPass / http://127.0.0.1:9001/
  ProxyPassReverse / http://127.0.0.1:9001/
  
  ErrorLog ${APACHE_LOG_DIR}/error.log
</VirtualHost>
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
The third one should also show "HTTP/1.1 200 Connection established" and some other junk. HOWEVER when you look at your Proxy status you should see this connection went out the Squid backend.
Relace the IP address with the host address of HAProxy.
```
curl -x 192.168.0.6:9100 http://192.168.0.6:9001/
curl -I -x 192.168.0.6:9100 https://sso.pokemon.com/sso/login
curl -I -x 192.168.0.6:9100 https://google.com
```

--------------------------------------------------
View the stats page to see that data went through all ends here: http://192.168.0.6:9100/haproxy?stats.
You should have a "proxy_in" as the frontend section, "rdm" as a backend, and "proxy_out" another backend.
All data should flow through the frontend. Then connections should show up for each curl you issue and go to the correct backend.
In "proxy_out", the "chk" column near the end is how many checks your proxies fail against the script.

--------------------------------------------------
I suggest testing this on one device to ensure it is working correctly before switch all devices.
Update the device proxy settings to use HAProxy. 
- iOS - Settings > Wifi > SSID > Proxy > Manual > Enter your information.
- Android ADB - adb shell settings put global http_proxy 192.168.0.6:9100 (Replace IP and Port with your information)

*Optional if you have resoultion problems with public addresses*
You may also want to set a public DNS since addresses have resolution problems. Google DNS are 8.8.8.8 and 8.8.4.4, Cloudflare 1.1.1.1 and 1.0.0.1, or any other public DNS will work.
- iOS - Settings > Wifi > SSID > DNS
- Android ADB - adb shell setprop net.eth0.dns1 8.8.8.8 
adb shell setprop net.eth0.dns2 4.4.4.4

In the MITM config, ensure your backend URL uses the IP address and port 9001 of the HAProxy server.
Check that the phone's or atv data makes it to the map and you should be done.

--------------------------------------------------
