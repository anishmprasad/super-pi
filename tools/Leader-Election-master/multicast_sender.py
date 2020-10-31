import socket
import struct
import time
import get_ip

def send():
	host = get_ip.get_lan_ip()
	MCAST_GRP = '224.1.1.1'
	MCAST_PORT = 5007
	sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
	sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 32)
	while True:
		sock.sendto(host, (MCAST_GRP, MCAST_PORT))
		time.sleep(3)