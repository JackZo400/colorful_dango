import paramiko
c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect('38.22.90.80', username='root', password='LtUp1IBLc8SBKKxn', timeout=10)
stdin, stdout, stderr = c.exec_command('echo CONNECTED && which dart 2>/dev/null && dart --version 2>/dev/null || echo NO_DART')
print(stdout.read().decode())
c.close()
