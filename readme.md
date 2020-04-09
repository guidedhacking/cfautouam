# cfautouam - CloudFlare Under Attack Mode Automation

[![](https://img.youtube.com/vi/gVRgeELT2JU/0.jpg)](https://youtu.be/gVRgeELT2JU)

### What does it do
Enables Cloudflare's Under Attack Mode based on CPU load percentage using the Cloudflare API.

### Why
Running your site on Under Attack Mode permanently is not great for visitors.  This script will enable it under high CPU load which is indicative of a DDOS attack.

### Warning
This is a beta script and I barely know what I'm doing so test this thoroughly before using.

### How?
It creates a service that runs on a timer, which executes our main shell script which gets the current CloudFlare Security Level and checks the CPU usage.  If CPU usage is above our defined limit, it uses the CloudFlare API to set the Security Level to Under Attack Mode.  If CPU usage normalizes and the time limit has passed, it will change the Security Level back to your defined "normal" Security Level.

### How to install

Navigate to the parent path where you want to install.  If you want to install to
/home/cfautouam then navigate to /home

```bash
wget https://raw.githubusercontent.com/guided-hacking/cfautouam/master/cfautouam.sh;
```

Define the parent path where you want to install the script, your Cloudflare email, API key, Zone ID, regular_status and regular_status_s as it related to your normal security level

```bash
mkdir cfautouam;
cp cfautouam.sh cfautouam/cfautouam.sh
cd cfautouam;
chmod +x cfautouam.sh;
./cfautouam.sh -install;
```

It's now installed and running from the defined parent path, check the logs and confirm it's working.  You can delete the original file.

After confirming it works, set debug level to 0.


### Command Line Arguments
```
-install        : installs and enables service
-uninstall      : uninstalls and then deletes the sub folder
-disable_script : temporarily disables the service from running
-enable_script  : re-enables the service
-enable_uam     : enables Under Attack Mode manually
-disable_uam    : disables Under Attack Mode manually
```

### Notes
This script was designed to run out of it's own separate folder, if you change that you may have problems.

### TODO
* Add more accurate CPU usage function
* Add error checking to command line arguments
