import socket
import binascii
import time
import threading
import thread
import get_ip


ips = {}
lock = threading.Lock()
def alive():
	while True:
		for ip in ips.keys():
			lock.acquire()
			if (time.time()-ips[ip])>5:
				ips.pop(ip)
			lock.release()
		time.sleep(5)


def receive():
	thread.start_new_thread(alive, ())
	MCAST_GRP = '224.1.1.1'
	MCAST_PORT = 5007
	sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
	try:
		sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
	except AttributeError:
		pass
	sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 32) 
	sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)

	sock.bind((MCAST_GRP, MCAST_PORT))
	host = get_ip.get_lan_ip()
	sock.setsockopt(socket.SOL_IP, socket.IP_MULTICAST_IF, socket.inet_aton(host))
	sock.setsockopt(socket.SOL_IP, socket.IP_ADD_MEMBERSHIP, 
									 socket.inet_aton(MCAST_GRP) + socket.inet_aton(host))

	while 1:
		try:
			data, addr = sock.recvfrom(1024)
			if data != host:
				lock.acquire()
				ips[data] = time.time()
				lock.release()
		except socket.error, e:
			print 'Expection'