```
sudo apt update
sudo apt install clamav clamav-daemon -y
sudo systemctl stop clamav-freshclam
sudo systemctl start clamav-daemon
sudo freshclam
sudo clamscan / -ir --exclude-dir=/usr/share/set --exclude-dir=/usr/share/doc --exclude-dir=/usr/share/powershell-empire --exclude-dir=/usr/share/windows-resources --exclude-dir=/usr/share/webshells --exclude-dir=/usr/share/metasploit-framework --exclude-dir=/usr/share/commix --exclude-dir=/usr/share/davtest --exclude-dir=/usr/share/exploitdb --exclude-dir=/usr/lib/passing-the-hash --exclude-dir=/usr/lib/python3/dist-packages/cme --exclude-dir=/var/lib/dpkg/info | tee ~/clam.log
```
