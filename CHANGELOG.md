# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.1 - 2023-11-18

### Added

* Support starting as an OTP application or in supervision
* Callbacks to support lifecycle events. See [Lifecycle events](https://hexdocs.pm/pint_broker/readme.html#lifecycle-events) for more info

## v1.0.0 - 2023-09-26

Initial release. See [README.md](README.md) for more information.

### Added

* Simple, unencrypted TCP connections
* [MQTT v3.1.1](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.pdf)
  * QoS 0
  * Connect, publish, subscribe, and unsubscribe
  * Ping requests
  * Rule forwarding (see below)
