package gotest

import (
	"dagger.io/dagger"
	"dagger.io/dagger/core"

	"universe.dagger.io/docker"
)

#SSH: {
	Key:        dagger.#Secret
	KnownHosts: dagger.#Secret
}

#GoTest: {
	// Package to test
	package: *"." | string

	ssh: #SSH

	#GoContainer & {
		sshKey:        ssh.Key
		sshKnownHosts: ssh.KnownHosts
		command: {
			name: "go"
			args: [package]
			flags: {
				test: true
				"-v": true
			}
		}
	}
}

// Build a go binary
#GoBuild: {
	// Source code
	source: dagger.#FS

	// Target package to build
	package: *"." | string

	ssh: #SSH

	// Target architecture
	arch?: string

	// Target OS
	os?: string

	// Build tags to use for building
	tags: *"" | string

	// LDFLAGS to use for linking
	ldflags: *"" | string

	env: [string]: string

	container: #GoContainer & {
		"source": source
		"env": {
			env
			if os != _|_ {
				GOOS: os
			}
			if arch != _|_ {
				GOARCH: arch
			}
		}
		sshKey:        ssh.Key
		sshKnownHosts: ssh.KnownHosts
		command: {
			name: "go"
			args: [package]
			flags: {
				build:      true
				"-v":       true
				"-tags":    tags
				"-ldflags": ldflags
				"-o":       "/output/"
			}
		}
		export: directories: "/output": _
	}

	// Directory containing the output of the build
	output: container.export.directories."/output"
}

// A standalone go environment to run go command
#GoContainer: {
	// Container app name
	name: *"go_builder" | string

	// Source code
	source: dagger.#FS

	sshKey:        dagger.#Secret
	sshKnownHosts: dagger.#Secret

	// Use go image
	_image: #GoImage

	_sourcePath:        "/src"
	_modCachePath:      "/root/.cache/go-mod"
	_buildCachePath:    "/root/.cache/go-build"
	_sshPath:           "/root/.ssh/id_rsa"
	_sshKnownHostsPath: "/root/.ssh/known_hosts"

	docker.#Run & {
		input:   *_image.output | docker.#Image
		workdir: _sourcePath
		mounts: {
			"source": {
				dest:     _sourcePath
				contents: source
			}
			"go mod cache": {
				contents: core.#CacheDir & {
					id: "\(name)_mod"
				}
				dest: _modCachePath
			}
			"go build cache": {
				contents: core.#CacheDir & {
					id: "\(name)_build"
				}
				dest: _buildCachePath
			}
			"ssh key": {
				contents: sshKey
				dest:     _sshPath
			}
			"ssh Known Hosts": {
				contents: sshKnownHosts
				dest:     _sshKnownHostsPath
			}
		}
		env: GOMODCACHE: _modCachePath
	}
}

// Go image default version
_#DefaultVersion: "1.18"

// Build a go base image
#GoImage: {
	version: *_#DefaultVersion | string

	packages: [pkgName=string]: version: string | *""
	// FIXME Remove once golang image include 1.18 *or* go compiler is smart with -buildvcs
	packages: {
		git:     _
		openssh: _
		"alpine-sdk": _
	}

	// FIXME Basically a copy of alpine.#Build with a different image
	// Should we create a special definition?
	docker.#Build & {
		steps: [
			docker.#Pull & {
				source: "index.docker.io/golang:\(version)-alpine"
			},
			for pkgName, pkg in packages {
				docker.#Run & {
					command: {
						name: "apk"
						args: ["add", "\(pkgName)\(pkg.version)"]
						flags: {
							"-U":         true
							"--no-cache": true
						}
					}
				}
			},
			docker.#Run & {
				command: {
					name: "/bin/sh"
					args: ["-c", """
																	cat > /root/.gitconfig <<- EOM
												[url \"git@github.com:private\"]
													insteadof = https://github.com/private
												EOM"""]
				}
			},
		]
	}
}

dagger.#Plan & {
	client: {
		filesystem: "./": read: contents: dagger.#FS

		env: {
			SSH_KEY:         dagger.#Secret
			SSH_KNOWN_HOSTS: dagger.#Secret
			GOPRIVATE:       string
		}
	}

	actions: {
		build: #GoBuild & {
			source:  client.filesystem."./".read.contents
			package: "cmd/main.go"
			ssh: {
				Key:        client.env.SSH_KEY
				KnownHosts: client.env.SSH_KNOWN_HOSTS
			}
			env: GOPRIVATE: client.env.GOPRIVATE
		}

		test: #GoTest & {
			source:  client.filesystem."./".read.contents
			package: "./..."
			ssh: {
				Key:        client.env.SSH_KEY
				KnownHosts: client.env.SSH_KNOWN_HOSTS
			}
			env: GOPRIVATE: client.env.GOPRIVATE
		}
	}
}

