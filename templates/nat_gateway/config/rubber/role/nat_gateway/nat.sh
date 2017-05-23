<%
  @perms = 0744
  @path = '/etc/init.d/nat'
  @post = 'ln -sf /etc/init.d/nat /etc/rc2.d/S90nat && service nat start'

  vpc_cidr = Rubber.config.cloud_providers.aws.vpc_cidr
%>
echo -e "\n\nLoading simple rc.firewall-iptables version $FWVER..\n"
DEPMOD=/sbin/depmod
MODPROBE=/sbin/modprobe

#======================================================================
#== No editing beyond this line is required for initial MASQ testing ==
echo -en "   loading modules: "
echo "  - Verifying that all kernel modules are ok"
$DEPMOD -a
echo "----------------------------------------------------------------------"
echo -en "ip_tables, "
$MODPROBE ip_tables
echo -en "nf_conntrack, "
$MODPROBE nf_conntrack
echo -en "nf_conntrack_ftp, "
$MODPROBE nf_conntrack_ftp
echo -en "nf_conntrack_irc, "
$MODPROBE nf_conntrack_irc
echo -en "iptable_nat, "
$MODPROBE iptable_nat
echo -en "nf_nat_ftp, "
$MODPROBE nf_nat_ftp
echo "----------------------------------------------------------------------"
echo -e "   Done loading modules.\n"
echo "   Enabling forwarding.."
echo "1" > /proc/sys/net/ipv4/ip_forward
echo "   Enabling DynamicAddr.."
echo "1" > /proc/sys/net/ipv4/ip_dynaddr
echo "   Disabling redirects.."
echo "0" > /proc/sys/net/ipv4/conf/eth0/send_redirects
echo "   Clearing any existing NAT rules and setting default policy.."

# Share public Internet connection.
iptables --table nat --flush
iptables -t nat -C POSTROUTING -o eth0 -s <%= vpc_cidr %> -j MASQUERADE 2> /dev/null || iptables -t nat -A POSTROUTING -o eth0 -s <%= vpc_cidr %> -j MASQUERADE

echo -e "\nrc.firewall-iptables v$FWVER done.\n"

