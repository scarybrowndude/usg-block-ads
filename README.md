# usg-block-ads
This script gets various anti-ad hosts files, merges, sorts, and uniques, then installs.


1. SSH to your USG gateway
2. sudo to root

    `sudo -i`
3. Download script

    `curl https://raw.githubusercontent.com/scarybrowndude/usg-block-ads/master/buildhosts-unifi.sh > /usr/local/sbin/buildhosts-unifi.sh`

4.  Make script executable

    `chmod 755 /usr/local/sbin/buildhosts-unifi.sh`

5. Run once to make sure it works

    `/usr/local/sbin/buildhosts-unifi.sh`

6. Make a cron job to run it every week ( eg: runs every Thursday at 4:44AM) 

    `echo '44 4 * * 4 root /usr/local/sbin/buildhosts-unifi.sh' > /etc/cron.d/buildhosts`
