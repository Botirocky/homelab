import json
import os
from datetime import timedelta

from django.contrib.auth.models import User
from hc.accounts.models import Project
from hc.accounts.views import _make_user
from hc.api.models import Channel, Check

email = os.environ["PARK_EMAIL"]
jelszo = os.environ["PARK_JELSZO"]
ntfy = os.environ.get("PARK_NTFY", "")

u = User.objects.filter(email=email).first()
if u is None:
    u = _make_user(email)
u.is_staff = True
u.is_superuser = True
u.set_password(jelszo)
u.save()

projekt = Project.objects.filter(owner=u).first()
Check.objects.filter(project=projekt, name="My First Check", n_pings=0).delete()
if projekt.name != "Szerverpark":
    projekt.name = "Szerverpark"
    projekt.save()

csatorna = None
if ntfy.startswith("http"):
    alap, _, tema = ntfy.rstrip("/").rpartition("/")
    csatorna = Channel.objects.filter(project=projekt, kind="ntfy").first()
    if csatorna is None:
        csatorna = Channel(project=projekt, kind="ntfy", name="ntfy")
    csatorna.value = json.dumps({"topic": tema, "url": alap, "priority": 4, "priority_up": 3, "token": None})
    csatorna.save()

for nev, ido, turem, cimke in json.loads(os.environ.get("PARK_FIGYELOK", "[]")):
    c = Check.objects.filter(project=projekt, name=nev).first()
    if c is None:
        c = Check(project=projekt, name=nev, kind="simple")
    c.timeout = timedelta(hours=ido)
    c.grace = timedelta(hours=turem)
    c.tags = cimke
    c.save()
    if csatorna is not None:
        csatorna.checks.add(c)
    print(f"PING {nev} {c.code}")
