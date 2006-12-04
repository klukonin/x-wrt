#!/usr/bin/webif-page
<?
. "/usr/lib/webif/webif.sh"
###################################################################
# WAN and LAN configuration page
#
# Description:
#	Configures basic WAN and LAN interface settings.
#
# Author(s) [in order of work date]:
#       Original webif authors of wan.sh and lan.sh
#	Jeremy Collake <jeremy.collake@gmail.com>
#
# Major revisions:
#
# NVRAM variables referenced:
#
# Configuration files referenced:
#   none
#

header "Network" "WAN-LAN" "@TR<<WAN-LAN Configuration>>" ' onload="modechange()" ' "$SCRIPT_NAME"

load_settings network

FORM_wandns="${wan_dns:-$(uci get network.wan.dns)}"
LISTVAL="$FORM_wandns"
handle_list "$FORM_wandnsremove" "$FORM_wandnsadd" "$FORM_wandnssubmit" 'ip|FORM_dnsadd|@TR<<WAN DNS Address>>|required' && {
	FORM_wandns="$LISTVAL"
	uci_set "network" "wan" "dns" "$FORM_wandns"
}
FORM_wandnsadd=${FORM_wandnsadd:-192.168.1.1}

if empty "$FORM_submit"; then
	FORM_wan_proto=${FORM_wan_proto:-$(uci get network.wan.proto)}
	case "$FORM_wan_proto" in
		# supported types
		static|dhcp|pptp|pppoe|wwan) ;;
		# otherwise select "none"
		*) FORM_wan_proto="none";;
	esac

	# pptp, dhcp and static common
	FORM_wan_ipaddr=${wan_ipaddr:-$(uci get network.wan.ipaddr)}
	FORM_wan_netmask=${wan_netmask:-$(uci get network.wan.netmask)}
	FORM_wan_gateway=${wan_gateway:-$(uci get network.wan.gateway)}

	# ppp common
	#TODO: verify all ppp variables still work under kamikaze.
	FORM_ppp_username=${ppp_username:-$(uci get network.wan.username)}
	FORM_ppp_passwd=${ppp_passwd:-$(uci get network.wan.passwd)}
	FORM_ppp_idletime=${ppp_idletime:-$(uci get network.wan.idletime)}
	FORM_ppp_redialperiod=${ppp_redialperiod:-$(uci get network.wan.redialperiod)}
	FORM_ppp_mtu=${ppp_mtu:-$(uci get network.wan.mtu)}

	redial=${ppp_demand:-$(uci get network.wan.demand)}
	case "$redial" in
		1|enabled|on) FORM_ppp_redial="demand";;
		*) FORM_ppp_redial="persist";;
	esac

	FORM_pptp_server_ip=${pptp_server_ip:-$(uci get network.wan.server)}
	
	# umts apn
	FORM_wwan_service=${wwan_service:-$(uci get network.wan.service)}
	FORM_wwan_pincode="-@@-"
	FORM_wwan_country=${wwan_country:-$(uci get network.wan.country)}
	FORM_wwan_apn=${wwan_apn:-$(uci get network.wan.apn)}
	FORM_wwan_username=${wwan_username:-$(uci get network.wan.username)}
	FORM_wwan_passwd=${wwan_passwd:-$(uci get network.wan.passwd)}
else
	SAVED=1

	empty "$FORM_wan_proto" && {
		ERROR="@TR<<No WAN Proto|No WAN protocol has been selected>>"
		return 255
	}

	case "$FORM_wan_proto" in
		static)
			V_IP="required"
			V_NM="required"
			;;
		pptp)
			V_PPTP="required"
			;;
	esac

validate <<EOF
ip|FORM_wan_ipaddr|@TR<<IP Address>>|$V_IP|$FORM_wan_ipaddr
netmask|FORM_wan_netmask|@TR<<WAN Netmask>>|$V_NM|$FORM_wan_netmask
ip|FORM_wan_gateway|@TR<<Default Gateway>>||$FORM_wan_gateway
ip|FORM_pptp_server_ip|@TR<<PPTP Server IP>>|$V_PPTP|$FORM_pptp_server_ip
EOF
	equal "$?" 0 && {
		uci_set "network" "wan" "proto" "$FORM_wan_proto"

		# Settings specific to one protocol type
		case "$FORM_wan_proto" in
			static) uci_set "network" "wan" "gateway" "$FORM_wan_gateway" ;;
			pptp) uci_set "network" "wan" "server" "$FORM_pptp_server_ip" ;;
			wwan)
			uci_set "network" "wan" "service" "$FORM_wwan_service"
			if ! equal "$FORM_wwan_pincode" "-@@-"; then
				uci_set "network" "wan" "pincode" "$FORM_wwan_pincode"
			fi
			uci_set "network" "wan" "country" "$FORM_wwan_country"
			uci_set "network" "wan" "apn" "$FORM_wwan_apn"
			uci_set "network" "wan" "username" "$FORM_wwan_username"
			uci_set "network" "wan" "passwd" "$FORM_wwan_passwd"
			;;
		esac

		# Common settings for PPTP, Static and DHCP
		case "$FORM_wan_proto" in
			pptp|static|dhcp)
				uci_set "network" "wan" "ipaddr" "$FORM_wan_ipaddr"
				uci_set "network" "wan" "netmask" "$FORM_wan_netmask"
			;;
		esac

		# Common PPP settings
		case "$FORM_wan_proto" in
			pppoe|pptp|wwan)
				empty "$FORM_ppp_username" || uci_set "network" "wan" "username" "$FORM_ppp_username"
				empty "$FORM_ppp_passwd" || uci_set "network" "wan" "passwd" "$FORM_ppp_passwd"

				# These can be blank
				uci_set "network" "wan" "idletime" "$FORM_ppp_idletime"
				uci_set "network" "wan" "redialperiod" "$FORM_ppp_redialperiod"
				uci_set "network" "wan" "mtu" "$FORM_ppp_mtu"

				uci_set "network" "wan" "ifname" "ppp0"

				case "$FORM_ppp_redial" in
					demand)
						uci_set "network" "wan" "demand" "1"
						;;
					persist)
						uci_set "network" "wan" "demand" ""
						;;
				esac
			;;
			*)
				wan_ifname=${wan_ifname:-$(uci get network wan ifname)}
				[ -z "$wan_ifname" -o "${wan_ifname%%[0-9]*}" = "ppp" ] && {
					wan_device=${wan_device:-$(uci get nework wan device)}
					wan_device=${wan_device:-vlan1}
					uci_set "network" "wan" "ifname" "$wan_device"
				}
			;;
		esac
	}
fi

# detect pptp package and compile option
[ -x "/sbin/ifup.pptp" ] && {
	PPTP_OPTION="option|pptp|PPTP"
	PPTP_SERVER_OPTION="field|PPTP Server IP|pptp_server|hidden
text|pptp_server_ip|$FORM_pptp_server_ip"
}
[ -x "/sbin/ifup.pppoe" ] && {
	PPPOE_OPTION="option|pppoe|PPPoE"
}

[ -x /sbin/ifup.wwan ] && {
	WWAN_OPTION="option|wwan|UMTS/GPRS"
	WWAN_COUNTRY_LIST=$(
		awk '	BEGIN{FS=":"}
			$1 ~ /[ \t]*#/ {next}
			{print "option|" $1 "|@TR<<" $2 ">>"}' < /usr/lib/webif/apn.csv
	)
	JS_APN_DB=$(
		awk '	BEGIN{FS=":"}
			$1 ~ /[ \t]*#/ {next}
			{print "	apnDB." $1 " = new Object;"
			 print "	apnDB." $1 ".name = \"" $3 "\";"
			 print "	apnDB." $1 ".user = \"" $4 "\";"
			 print "	apnDB." $1 ".pass = \"" $5 "\";\n"}' < /usr/lib/webif/apn.csv
	)
}

cat <<EOF
<script type="text/javascript" src="/webif.js "></script>
<script type="text/javascript">
<!--
function setAPN(element) {
	var apnDB = new Object();

$JS_APN_DB

	document.getElementById("wwan_apn").value = apnDB[element.value].name;
	document.getElementById("wwan_username").value = apnDB[element.value].user;
	document.getElementById("wwan_passwd").value = apnDB[element.value].pass;
}

function modechange()
{
	var v;
	v = (isset('wan_proto', 'pppoe') || isset('wan_proto', 'pptp'));
	set_visible('ppp_settings', v);
	set_visible('username', v);
	set_visible('passwd', v);
	set_visible('redial', v);
	set_visible('mtu', v);
	set_visible('demand_idletime', v && isset('ppp_redial', 'demand'));
	set_visible('persist_redialperiod', v && !isset('ppp_redial', 'demand'));

	v = (isset('wan_proto', 'static') || isset('wan_proto', 'pptp') || isset('wan_proto', 'dhcp'));
	set_visible('wan_ip_settings', v);
	set_visible('field_wan_ipaddr', v);
	set_visible('field_wan_netmask', v);

	v = isset('wan_proto', 'static');
	set_visible('field_wan_gateway', v);
	set_visible('wan_dns', v);

	v = isset('wan_proto', 'pptp');
	set_visible('pptp_server', v);
	
	v = isset('wan_proto', 'wwan');
	set_visible('wwan_service', v);
	set_visible('wwan_sim_settings', v);
	set_visible('apn_settings', v);

	hide('save');
	show('save');
}
-->
</script>
EOF

display_form <<EOF
onchange|modechange
start_form|@TR<<WAN Configuration>>
field|@TR<<Connection Type>>
select|wan_proto|$FORM_wan_proto
option|none|@TR<<No WAN#None>>
option|dhcp|@TR<<DHCP>>
option|static|@TR<<Static IP>>
$PPPOE_OPTION
$WWAN_OPTION
$PPTP_OPTION
helplink|http://wiki.openwrt.org/OpenWrtDocs/Configuration#head-b62c144b9886b221e0c4b870edb0dd23a7b6acab
end_form

start_form|@TR<<IP Settings>>|wan_ip_settings|hidden
field|@TR<<WAN IP Address>>|field_wan_ipaddr|hidden
text|wan_ipaddr|$FORM_wan_ipaddr
field|@TR<<Netmask>>|field_wan_netmask|hidden
text|wan_netmask|$FORM_wan_netmask
field|@TR<<Default Gateway>>|field_wan_gateway|hidden
text|wan_gateway|$FORM_wan_gateway
$PPTP_SERVER_OPTION
helpitem|WAN IP Settings
helptext|Helptext WAN IP Settings#IP Settings are optional for DHCP and PPTP. They are used as defaults in case the DHCP server is unavailable.
end_form

start_form|@TR<<WAN DNS Servers>>|wan_dns|hidden
listedit|wandns|$SCRIPT_NAME?wan_proto=static&amp;|$FORM_wandns|$FORM_wandnsadd
helpitem|Note
helptext|Helptext WAN DNS save#You should save your settings on this page before adding/removing DNS servers
end_form

start_form|@TR<<Preferred Connection Type>>|wwan_service|hidden
field|@TR<<Connection Type>>
select|wwan_service|$FORM_wwan_service
option|umts_first|@TR<<UMTS first>>
option|umts_only|@TR<<UMTS only>>
option|gprs_only|@TR<<GPRS only>>
end_form

start_form|@TR<<SIM Configuration>>|wwan_sim_settings|hidden
field|@TR<<PIN Code>>
password|wwan_pincode|$FORM_wwan_pincode
end_form

start_form|@TR<<APN Settings>>|apn_settings|hidden
field|@TR<<Select Network>>
onchange|setAPN
select|wwan_country|$FORM_wwan_country
$WWAN_COUNTRY_LIST
onchange|
field|@TR<<APN Name>>
text|wwan_apn|$FORM_wwan_apn
field|@TR<<Username>>
text|wwan_username|$FORM_wwan_username
field|@TR<<Password>>
text|wwan_passwd|$FORM_wwan_passwd
end_form

start_form|@TR<<PPP Settings>>|ppp_settings|hidden
field|@TR<<Redial Policy>>|redial|hidden
select|ppp_redial|$FORM_ppp_redial
option|demand|@TR<<Connect on Demand>>
option|persist|@TR<<Keep Alive>>
field|@TR<<Maximum Idle Time>>|demand_idletime|hidden
text|ppp_idletime|$FORM_ppp_idletime
helpitem|Maximum Idle Time
helptext|Helptext Idle Time#The number of seconds without internet traffic that the router should wait before disconnecting from the Internet (Connect on Demand only)
field|@TR<<Redial Timeout>>|persist_redialperiod|hidden
text|ppp_redialperiod|$FORM_ppp_redialperiod
helpitem|Redial Timeout
helptext|Helptext Redial Timeout#The number of seconds to wait after receiving no response from the provider before trying to reconnect
field|@TR<<Username>>|username|hidden
text|ppp_username|$FORM_ppp_username
field|@TR<<Password>>|passwd|hidden
password|ppp_passwd|$FORM_ppp_passwd
field|@TR<<MTU>>|mtu|hidden
text|ppp_mtu|$FORM_ppp_mtu
end_form
EOF


FORM_landns="${lan_dns:-$(uci get network.lan.dns)}"
LISTVAL="$FORM_landns"
handle_list "$FORM_landnsremove" "$FORM_landnsadd" "$FORM_landnssubmit" 'ip|FORM_dnsadd|@TR<<DNS Address>>|required' && {
	FORM_landns="$LISTVAL"
	uci_set "network" "lan" "dns" "$FORM_landns"
}
FORM_landnsadd=${FORM_landnsadd:-192.168.1.1}

if empty "$FORM_submit"; then
	FORM_lan_ipaddr=${lan_ipaddr:-$(uci get network.lan.ipaddr)}
	FORM_lan_netmask=${lan_netmask:-$(uci get network.lan.netmask)}
	FORM_lan_gateway=${lan_gateway:-$(uci get network.lan.gateway)}
else
	SAVED=1
	validate <<EOF
ip|FORM_lan_ipaddr|@TR<<IP Address>>|required|$FORM_lan_ipaddr
netmask|FORM_lan_netmask|@TR<<Netmask>>|required|$FORM_lan_netmask
ip|FORM_lan_gateway|@TR<<Gateway>>||$FORM_lan_gateway
EOF
	equal "$?" 0 && {
		uci_set "network" "lan" "ipaddr" "$FORM_lan_ipaddr"
		uci_set "network" "lan" "netmask" "$FORM_lan_netmask"
		uci_set "network" "lan" "gateway" "$FORM_lan_gateway"
	}
fi

display_form <<EOF
start_form|@TR<<LAN Configuration>>
field|@TR<<LAN IP Address>>
text|lan_ipaddr|$FORM_lan_ipaddr
helpitem|IP Address
helptext|Helptext LAN IP Address#This is the address you want this device to have on your LAN.
field|@TR<<Netmask>>
text|lan_netmask|$FORM_lan_netmask
helpitem|Netmask
helptext|Helptext Netmask#This bitmask indicates what addresses are included in your LAN.
field|@TR<<Default Gateway>>
text|lan_gateway|$FORM_lan_gateway
end_form
start_form|@TR<<LAN DNS Servers>>
listedit|landns|$SCRIPT_NAME?|$FORM_landns|$FORM_landnsadd
helpitem|Note
helptext|Helptext LAN DNS save#You need save your settings on this page before adding/removing DNS servers
end_form
EOF
show_validated_logo

footer ?>

<!--
##WEBIF:name:Network:100:WAN-LAN
-->