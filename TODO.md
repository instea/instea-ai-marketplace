TODO ideas

# Dev container setup

* [x] - install gh CLI - but recommend it with read only access to dev container via project prefixed env from host
* [x] - post-create - install claude plugins
* [x] - skill shall first check if it is up to date (as it will be most likely from user local)
* [x] - allow claude to be updated - getting  `Auto-update failed: no write permission to npm prefix` message

All four shipped in project-setup 0.4.0. Follow-ups worth considering:

* [ ] - evals: the fixtures have no GitHub remote, so nothing exercises the gh CLI branch or the
        step 0 version check; add a fixture with a remote if we want those covered
* [ ] - docker-release-workflow could adopt scripts/check-plugin-version.sh in its own step 0
