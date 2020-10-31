from flask import Flask
from flask import request
from httplib import HTTPConnection
import urllib
import thread
import get_ip
from random import randint
import logging

log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

app = Flask(__name__)

participant = False
leader_UID = 0

my_UID = randint(1, 1000000)

ip = get_ip.get_lan_ip()
print(ip)


headers = {"Content-type": "application/x-www-form-urlencoded", "Accept": "text/plain"}

pi = raw_input("What is my port?: ")
next_pi = raw_input("What is the port of the node is next to me?: ")


def send_UID(UID, path):
	participant = True
	connection = HTTPConnection(ip, next_pi, timeout=10)
	connection.request("POST", ("/" + path), urllib.urlencode({'UID' : UID}), headers)
	response = connection.getresponse()


def compare(passed):
	global participant
	if (passed > my_UID):
		thread.start_new_thread(send_UID, (passed, "election"))
	elif (passed < my_UID and  participant == False):
		thread.start_new_thread(send_UID, (my_UID, "election"))
	elif (passed < my_UID and participant == True):
		print("Discarding election message")
	elif (passed == my_UID):
		participant = False
		thread.start_new_thread(send_UID, (my_UID, "leader"))




if (raw_input("Start the election? y/n: ")=='y'):
	thread.start_new_thread(send_UID, (my_UID, "election"))



@app.route('/election', methods=['POST'])
def election():
	passed_UID = int(request.form['UID'])
	thread.start_new_thread(compare, (passed_UID,))


@app.route('/leader', methods=['POST'])
def leader():
	global participant 
	participant = False
	leader_UID = int(request.form['UID'])
	if (my_UID == leader_UID):
		print("Everyone knows I am the leader now")
	else:
		print("Leader UID is  " + str(leader_UID))
		thread.start_new_thread(send_UID, (leader_UID, "leader"))




if __name__ == '__main__':
	app.run(port = int(pi), host='0.0.0.0')