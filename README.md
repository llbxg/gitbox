# GitBox

**Minimal self-hosted Git server**

A lightweight setup for hosting Git repositories locally with a simple web UI.

* Push and pull via SSH
* Browse repositories with cgit over HTTP
* Namespace: `repos/<name>.git`

~~~plaintext
                         +-----------------------------------------+
+--------+ git pull/push | +--------------------+ r/w +----------+ |
| Client +---------------|-+ git-ssh container  +-----+ Volume   | |
|        |               | | sshd + bare repos  |     | /srv/git | |
+------+-+               | +--------------------+     +---+------+ |
       |                 |                                |        |
       |       http      | +--------------------+  r/o    |        |
       +-----------------|-+ cgit-web container +---------+        |
                         | | lighttpd + cgit    |                  |
                         | +--------------------+                  |
                         +-----------------------------------------+
~~~

## Build & Run

~~~bash
sudo nerdctl compose up -d --build
~~~

## SSH Settings

### Config

~~~sshconfig
Host gitbox
    HostName localhost
    Port 2222
    User git
    IdentityFile <path_to_privatekey>
    IdentitiesOnly yes
~~~

### Keys

~~~bash
./tools/gbctl.sh key set "<path_to_publickey>"
~~~

### Verify

~~~bash
ssh -T gitbox
~~~

GitBox uses `git-shell`, so interactive shell access is disabled.

## Create a Repository

~~~bash
./tools/gbctl.sh repoctl create myrepo "My first repo"
~~~

## Push

~~~bash
git remote add origin gitbox:repos/myrepo.git
git push -u origin main
~~~

## repoctl

Manage repositories inside the container:

~~~bash
./tools/gbctl.sh repoctl --help
~~~

## Web UI

- <http://localhost:8080/repos/myrepo/>

## Mirror Repositories

GitBox supports mirroring external repositories under the `repos/` namespace.

### Create a Mirror

~~~bash
./tools/gbctl.sh mirror init git@github.com:llbxg/gitbox.git
./tools/gbctl.sh mirror init git@github.com:llbxg/gitbox.git team
./tools/gbctl.sh mirror init git@github.com:llbxg/gitbox.git team/custom.git
~~~

### Update a Mirror

~~~bash
./tools/gbctl.sh mirror update gitbox
./tools/gbctl.sh mirror update team/custom
./tools/gbctl.sh mirror update --all
~~~

### Clean Up Stale Local Mirrors

~~~bash
./tools/gbctl.sh mirror cleanup
./tools/gbctl.sh mirror cleanup --apply
~~~

## Back Up Volumes

Create and apply a backup archive for the `repos` and `ssh-data` volumes:

~~~bash
./tools/gbctl.sh backup create /tmp/gitbox-backup.tar.gz
./tools/gbctl.sh backup apply /tmp/gitbox-backup.tar.gz
~~~
