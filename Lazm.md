Yes — now the scope is clear. You need a PoC test checklist for an already-configured Endpoint Central test environment:

> “What operations should we actually perform against test Windows/Linux clients and servers to decide whether Endpoint Central works well enough for production?”



I would test the following.

Endpoint Central PoC — Operations Checklist

#	Test operation	Windows Client	Linux Client	Windows Server	Linux Server	Result

1	Agent communication	✓	✓	✓	✓	☐
2	Inventory scan	✓	✓	✓	✓	☐
3	OS patch detection	✓	✓	✓	✓	☐
4	OS patch installation	✓	✓	✓	✓	☐
5	Patch uninstall/rollback where supported	✓	✓	✓	✓	☐
6	Third-party application update	✓	✓	Optional	Optional	☐
7	Software installation	✓	✓	✓	✓	☐
8	Software uninstall	✓	✓	✓	✓	☐
9	Custom script execution	✓	✓	✓	✓	☐
10	File deployment	✓	✓	✓	✓	☐
11	Reboot management	✓	✓	✓	✓	☐
12	Remote troubleshooting	✓	✓	✓	✓	☐
13	Vulnerability scan	✓	✓	✓	✓	☐
14	Patch compliance/reporting	✓	✓	✓	✓	☐
15	Offline endpoint behavior	✓	✓	✓	✓	☐
16	Failed deployment handling	✓	✓	✓	✓	☐


1. Agent & Communication

On every test machine:

[ ] Confirm agent appears online in Endpoint Central

[ ] Force/trigger an inventory scan

[ ] Confirm hardware information is collected correctly

[ ] Confirm installed software/packages are detected

[ ] Restart the endpoint and verify it reconnects

[ ] Disconnect network temporarily and verify Endpoint Central shows it offline

[ ] Reconnect and verify agent recovers automatically

[ ] Compare Endpoint Central information with the actual machine


Pass: Endpoint is consistently manageable without manually repairing/restarting the agent.


---

2. Windows Client — Update Testing

This should be one of the main tests.

Take a Windows test PC that intentionally has some outstanding updates.

[ ] Scan for missing Windows updates

[ ] Confirm Endpoint Central detects them

[ ] Deploy one update manually

[ ] Deploy several updates together

[ ] Deploy a security/critical update

[ ] Schedule an update for a specific time

[ ] Test user notification before installation

[ ] Test reboot-required update

[ ] Test reboot notification/postponement

[ ] Restart PC

[ ] Rescan

[ ] Confirm installed patch disappears from missing-patch list

[ ] Confirm Endpoint Central reports deployment as successful


Also deliberately create a failure if practical:

[ ] Attempt deployment while machine is offline

[ ] Bring it online

[ ] Verify whether deployment retries

[ ] Check whether the console gives useful failure information



---

3. Linux Client — Update Testing

Use the distributions your company actually has.

[ ] Scan Linux client for available updates

[ ] Confirm missing packages/security updates

[ ] Deploy one package update

[ ] Deploy multiple updates

[ ] Verify package version actually changed

[ ] Test an update requiring restart if available

[ ] Reboot

[ ] Confirm agent reconnects

[ ] Rescan

[ ] Confirm Endpoint Central correctly reports new patch state

[ ] Test failure/retry behavior



---

4. Windows Server — Patching

For the Windows test server, simulate your real production server patching procedure.

Pre-patch

[ ] Scan server

[ ] Identify missing patches

[ ] Select only approved patches

[ ] Schedule patching for a maintenance window

[ ] Check whether reboot is required


Patch

[ ] Start deployment

[ ] Monitor installation

[ ] Confirm Endpoint Central reports progress

[ ] Reboot through Endpoint Central if required

[ ] Confirm server returns online


Post-patch

[ ] Confirm Endpoint Central agent reconnects

[ ] Verify important Windows services are running

[ ] Verify server/application functionality

[ ] Rescan server

[ ] Confirm patches installed

[ ] Confirm no false missing-patch results

[ ] Generate patch report


This is probably one of the most important PoC scenarios.


---

5. Linux Server — Patching

Do the equivalent on the Linux test server:

[ ] Scan for missing patches

[ ] Identify security updates

[ ] Identify normal package updates

[ ] Identify kernel update if one is available

[ ] Select approved updates

[ ] Schedule deployment

[ ] Deploy

[ ] Monitor package installation

[ ] Check Endpoint Central status

[ ] Reboot if required

[ ] Confirm server returns online

[ ] Confirm Endpoint Central agent reconnects

[ ] Verify important services

[ ] Verify application functionality

[ ] Verify package/kernel versions

[ ] Rescan

[ ] Confirm patch compliance


For Linux in particular, pay attention to whether Endpoint Central gives understandable information when the underlying package manager/repository encounters a problem.


---

6. Software Deployment

Pick harmless test software appropriate for the environment.

Windows

[ ] Install application remotely

[ ] Confirm installation

[ ] Upgrade application

[ ] Confirm new version

[ ] Uninstall application

[ ] Confirm removal

[ ] Deploy to multiple test PCs simultaneously


Linux

[ ] Install test package

[ ] Verify package

[ ] Upgrade package

[ ] Remove package

[ ] Confirm Endpoint Central reports each operation correctly


For servers, repeat at least one software deployment so you know server targeting works as expected.


---

7. Script Deployment

This is important if your administrators use PowerShell/Bash.

Windows

Run a harmless PowerShell script such as one that creates a test directory/file.

[ ] Deploy PowerShell script

[ ] Verify execution

[ ] Verify execution account/permissions

[ ] Check returned status

[ ] Test script with arguments

[ ] Test intentionally failing script

[ ] Check error reporting


Linux

Do the equivalent with Bash.

[ ] Deploy Bash script

[ ] Verify execution

[ ] Verify permissions

[ ] Test arguments

[ ] Verify output/status

[ ] Test intentionally failing script

[ ] Check error reporting


This answers an important PoC question: Can administrators reliably replace some manual/SSH/PowerShell operations with Endpoint Central?


---

8. File Deployment

Test basic configuration-file distribution.

For example:

endpoint-central-test.txt

[ ] Push file to Windows client

[ ] Push file to Linux client

[ ] Push file to Windows server

[ ] Push file to Linux server

[ ] Confirm correct destination

[ ] Replace/update existing file

[ ] Verify permissions/ownership on Linux

[ ] Confirm result from Endpoint Central



---

9. Remote Administration

Test whatever remote-management functionality your planned license provides.

Windows client

[ ] Remote desktop/control

[ ] View processes

[ ] Start/stop test service

[ ] File access/transfer

[ ] Remote command where supported

[ ] User notification/consent behavior


Servers/Linux

[ ] Remote management capability

[ ] Process/service management

[ ] Command/script execution

[ ] File operations


Also check whether actions are properly logged so you know who performed what operation against which endpoint.


---

10. Vulnerability Detection

If vulnerability management is part of the solution being evaluated:

[ ] Scan all test machines

[ ] Identify missing security updates

[ ] Identify vulnerable/outdated software

[ ] Check severity classification

[ ] Remediate one finding

[ ] Rescan

[ ] Confirm finding disappears

[ ] Verify vulnerability report updates


The important test isn't merely whether it detects something; test the full:

Detect → remediate → rescan → verify

cycle.


---

11. Failure Scenarios

I'd definitely include these in the PoC because normal successful deployments don't tell you enough.

Scenario	Expected behavior

Endpoint powered off during scheduled job	Job waits/retries appropriately
Endpoint loses network	Recovers after connection returns
Endpoint rebooted	Agent reconnects
Patch fails	Clear failure status/error
Script returns error	Failure correctly reported
Software install fails	Useful error/status
Server rebooted	Returns to managed state
Agent service stopped	Endpoint becomes unavailable/detected
Agent restarted	Management resumes
Multiple endpoints targeted	Correct endpoints receive operation


Test at least several of these deliberately.


---

12. Reporting

After you've performed all these operations, test whether Endpoint Central gives the administrators useful evidence.

[ ] List patched endpoints

[ ] List unpatched endpoints

[ ] Show failed patches

[ ] Show missing critical patches

[ ] Show software inventory

[ ] Show OS inventory

[ ] Show offline/unreachable endpoints

[ ] Show deployment history

[ ] Show vulnerability status

[ ] Export report

[ ] Confirm report values against test machines


What I Would Consider the Core PoC

If your manager wants the checklist to stay reasonably small, these are the tests I wouldn't remove:

1. Windows client: detect updates → deploy → reboot → rescan.


2. Linux client: detect updates → deploy → verify package → rescan.


3. Windows server: detect patches → scheduled deployment → reboot → service health check → rescan.


4. Linux server: detect patches → deploy → reboot/kernel verification → service health check → rescan.


5. Install, update and uninstall software.


6. Run PowerShell and Bash scripts remotely.


7. Push/update a file.


8. Perform remote troubleshooting/management.


9. Take an endpoint offline and test recovery/retry.


10. Cause a harmless deployment failure and evaluate error reporting.


11. Detect a vulnerability → remediate → rescan.


12. Generate patch/compliance/deployment reports.



For every item, I'd give the testers four columns:

Operation | Expected Result | Actual Result | Pass/Fail

That turns the checklist into something your team can actually execute and then hand to management as evidence for whether Endpoint Central is suitable.Yes. Endpoint Central has predefined/script-template functionality in addition to scripts you write yourself.

For your PoC checklist, I’d separate them into:

Predefined scripts / Script Repository — ready-made scripts provided through Endpoint Central for common administrative tasks. Test several relevant ones on Windows/Linux and verify the result.

Custom scripts — your own PowerShell, Batch, Bash, etc., uploaded or created for company-specific operations.


So instead of only having “Custom Script Execution”, your checklist should contain:

Test	Windows Client	Linux Client	Windows Server	Linux Server

Execute predefined/repository script	✓	✓*	✓	✓*
Verify predefined script result	✓	✓*	✓	✓*
Execute custom script	✓	✓	✓	✓
Custom script with parameters	✓	✓	✓	✓
Failed script/error reporting	✓	✓	✓	✓


*Availability of individual predefined scripts depends on OS and the particular script.

For the test environment, I'd explicitly test both because that's useful information for deciding whether Endpoint Central can reduce the amount of scripting administrators have to maintain themselves.

If you want, I can also redo the entire checklist with Endpoint Central's actual operational categories/features (patching, predefined configurations, scripts, software deployment, remote operations, etc.) and remove the less relevant tests. That would probably be closer to what your manager expects.
