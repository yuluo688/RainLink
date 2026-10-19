#!/usr/bin/python3
"""Disposable-VM polkit agent fixture; never requests or stores a password."""

import ctypes
import json
import os
from pathlib import Path
import sys

import dbus
import dbus.mainloop.glib
import dbus.service


AUTHORITY = "org.freedesktop.PolicyKit1.Authority"
AGENT = "org.freedesktop.PolicyKit1.AuthenticationAgent"
OBJECT = "/org/rainlink/QA/AuthenticationAgent"


class Dismissed(dbus.DBusException):
    _dbus_error_name = "org.freedesktop.PolicyKit1.Error.Cancelled"


def event(name):
    print(json.dumps({"event": name}), flush=True)


class Agent(dbus.service.Object):
    def __init__(self, bus, scenario):
        super().__init__(bus, OBJECT)
        self.scenario = scenario
        self.pending = {}

    @dbus.service.method(AGENT, in_signature="sssa{ss}sa(sa{sv})", out_signature="", async_callbacks=("reply", "fail"))
    def BeginAuthentication(self, action, message, icon, details, cookie, identities, reply, fail):
        if action != "org.freedesktop.policykit.exec" or not identities:
            fail(Dismissed("Unexpected QA authentication action"))
            return
        event("began")
        if self.scenario == "agent-reject":
            fail(Dismissed("QA agent dismissed authentication"))
        else:
            self.pending[str(cookie)] = fail

    @dbus.service.method(AGENT, in_signature="s", out_signature="")
    def CancelAuthentication(self, cookie):
        failure = self.pending.pop(str(cookie), None)
        if failure is None:
            raise Dismissed("Unknown QA authentication request")
        failure(Dismissed("QA authentication request revoked"))
        event("cancelled")


def main():
    if os.environ.get("RAINLINK_TEST_AUTH_AGENT") != "disposable-vm" or os.geteuid() != 65534:
        raise SystemExit("Authentication fixture requires disposable VM ordinary UID")
    pid, scenario = int(sys.argv[1]), sys.argv[2]
    if scenario not in {"cancel", "eof", "agent-reject"}:
        raise SystemExit("Invalid QA scenario")
    # The broker itself owns the polkit subject; no login desktop is simulated.
    stat = Path(f"/proc/{pid}/stat").read_text()
    start_time = int(stat[stat.rfind(")") + 2:].split()[19])
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    authority = dbus.Interface(bus.get_object("org.freedesktop.PolicyKit1", "/org/freedesktop/PolicyKit1/Authority"), AUTHORITY)
    subject = ("unix-process", {"pid": dbus.UInt32(pid), "start-time": dbus.UInt64(start_time), "uid": dbus.Int32(65534)})
    agent = Agent(bus, scenario)
    authority.RegisterAuthenticationAgent(subject, "C", OBJECT, signature="(sa{sv})ss")
    event("registered")
    # dbus-python's GLib integration only needs libglib. Avoid adding a GUI or
    # PyGObject dependency for this protocol fixture.
    glib = ctypes.CDLL("libglib-2.0.so.0")
    glib.g_main_context_iteration.argtypes = [ctypes.c_void_p, ctypes.c_int]
    glib.g_main_context_iteration.restype = ctypes.c_int
    try:
        while True:
            glib.g_main_context_iteration(None, 1)
    finally:
        authority.UnregisterAuthenticationAgent(subject, OBJECT, signature="(sa{sv})s")
        agent.remove_from_connection()


if __name__ == "__main__":
    main()
