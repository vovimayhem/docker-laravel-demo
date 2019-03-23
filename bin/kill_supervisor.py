#!/usr/bin/env python

"""
Script used to kill supervisord in case one of the child processes (nginx,
uwsgi) exits.
"""
from sys import stdin, stdout, stderr
import os
import signal

def write_stdout(s):
    stdout.write(s)
    stdout.flush()
def write_stderr(s):
    stderr.write(s)
    stderr.flush()

def main():
    while 1:
        write_stdout('READY\n')
        line = stdin.readline()
        write_stdout('This line kills supervisor: ' + line)
        try:
            pidfile = open('/usr/src/tmp/pids/supervisord.pid', 'r')
            pid = int(pidfile.readline())
            os.kill(pid, signal.SIGQUIT)
        except Exception as e:
            write_stdout('Could not kill supervisor: %s' % e)
        write_stdout('RESULT 2\nOK')

if __name__ == '__main__':
   main()
