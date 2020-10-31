from blessed import Terminal
from httplib import HTTPConnection
import urllib
import time
import multicast_receiver
import multicast_sender
import random
import screen_color

term = Terminal()
height, width = term.height, term.width
params = {'token' : 0}
headers = {"Content-type": "application/x-www-form-urlencoded", "Accept": "text/plain"}

def connect():
	while len(multicast_receiver.ips) < 1:
		pass
	try:
		multicast_receiver.lock.acquire()
		connection = HTTPConnection(random.choice(list(multicast_receiver.ips.keys())), 5000, timeout=10)
		multicast_receiver.lock.release()
		connection.request("POST", "/", urllib.urlencode(params), headers)
		response = connection.getresponse()
		return True
	except multicast_receiver.socket.error:
		return False


def send_token():
	time.sleep(3)
	if connect() == False:
		send_token()
	else:
		params['token'] = 0
		screen_color.color("red")
	return 1