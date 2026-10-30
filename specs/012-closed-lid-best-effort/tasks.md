# Tasks: Closed-Lid Best-Effort Mode

> **SUPERSEDED for product deployment (2026-10-30):** the exclusive-create / no-adoption / one-use admission requirements in this document are replaced by the persistent-helper model of [spec 014](../014-persistent-helper/spec.md) and [ADR 0001](../../docs/adr/0001-persistent-helper-and-strict-experimental-mode.md). The mechanism described here remains as the experimental **Strict** mode, frozen. Evidence and dated records below are kept as history; per-episode approval is now an owner QA discipline, not a product requirement. No gate passed by this change.


**OWNER DECISION: preserve exclusive-create/one-use; Installer continuation closed/NO-GO.** [Decision](../../docs/qa/preview-evidence/macos-auth-v3-installer-contract-design-2026-10-27/owner-preserve-invariants-decision.json); no weaker operator-managed contract, no package/install/sign/receipt/root action or new execution budget. Retain evidence/failures and disabled draft; no equivalent fake/archive loop or task/root/admission/auth/power/feature/shipping credit. Reopen only for a mechanism meeting unchanged invariants or explicit later policy change.

**Latest: [native bound-self-image eight stages reviewed PASS](../../docs/qa/macos-auth-v3-native-bound-self-image-01-result.md)** b4681d175/result00597ec9…/reviewbd5c6d97…; parser+build/display/run0/compiler-native stderr0/9FDs/3SHA/2code samples/54ACLqueries/9closes, UID501.186bound+324QA+323parent matched;scope31a9fa36… consumed. [Deployment decision pending](../../docs/design/baseline-ack-v2/post-composition-deployment-decision-2026-10-27.md): trusted privileged argv/admission still absent; no root/auth/power/task/shipping credit or further execution budget.

**Latest: [native held-self-image eight checks reviewed PASS](../../docs/qa/macos-auth-v3-native-held-self-image-01-result.md)** b21c9ef2c/result678ed9bd…/reviewdf47bc27…; build0/run0/stderr0, sameFD3/twoSHA/ACLqueries6/open1/close1/UID501/root-policy refused.173bound+324QA+323parent hashes matched;scope3ed6552c… consumed. No root/SecCode/protected-parent/runtimeclosure/auth/power/task/shipping credit.

**Latest completed: [self-image v6 policy-fake8 reviewed PASS](../../docs/qa/macos-auth-v3-self-image-v6-01-result.md)** bf4b36352/result8fd3a01e…/reviewa47b6984…; build0/run0/stderr0/exact8PASS. Scope222b4268… consumed;162bound+324QA+323parent hashes matched, no native producer/retainedFD/root/admission/power/task/shipping credit. Next [actual held-self-FD source plan](../../docs/design/baseline-ack-v2/native-held-self-image-next-step-2026-10-27.md) requires separate finite authority, not another policy-fake replay.

**Historical correction: [self-image diagnosis/authority correction; v5 HELD](../../docs/qa/macos-auth-v3-self-image-correction-2026-10-27.md)** V4 compile0/run3; two bodies completed/third failed/five not reached. `0755 & 0022 == 0`: test expects stricter policy, not compiler failure. V4 lacked fresh specific approval. V5 exact0500 source only; no capture/build/run. Open-failure cleanup, default drift, RUN order and unused gate need separately scoped repairs. No task/root/admission/power/shipping credit.


**Latest: [composed ownUID native diagnostic reviewed PASS](../../docs/qa/macos-auth-v3-native-composed-01-result.md)** bcde91175/fake8+build/display/runall0/samePIDself-before/leaf/self-after/checkedclose. Scope150d36c4… consumed;2dirs/1DATA retained/UID501/rootpolicyrefused. No root/admission/consent/receipt/atomicorigin/closure/task/shipping credit or sign/install/otherPID/credential/IPC/auth/power/capsule. Next separateunarmedrootentry sourceplan needs finite nonroot scope.

**Latest: [own-codev2 fake8/build/display/UID501API correlation reviewed PASS](../../docs/qa/macos-auth-v3-own-code-v2-01-result.md)** bdb2520a2/3exit0/APIstatuses0,0,0/CDHash0365528e… equalsdisplay/new35944B imageb197998b…. Scope10f49f92… consumed;SecBase+paths only/oldfailure retained. No root/consent/atomicorigin/closure/admission/task/shipping credit or sign/install/otherPID/credential/IPC/auth/power. Next combinedself+leaf sourceplan requires freshfinite scope.

**Latest: [own-code01 compile FAILURE,phase HALTED](../../docs/qa/macos-auth-v3-own-code-01-result.md)** bde7f3462/fake8PASS+clangexit1/3undeclarederrSecSuccess/missingSecBase.h. No display/native run/executable;scope0bb314fe… consumed/no repair/retry. New attempt requires freshsource/scope/output/permission. Prior evidence preserved;no root/sign/install/otherPID/credential/IPC/auth/power/task/shipping credit.

**Latest: [static fake8/four inspectors complete,ROOT ADMISSION WITHHELD](../../docs/qa/macos-auth-v3-native-static-01-result.md)** b584766f8/4exit0/checkedclose;CDHashe094105c…/flags0x20002/no staticruntimeflag,entitlementsno-data≠parsed{}. LibSystem/dyld/noRPATH not runtimeclosure. Scope6a674efa… consumed;seven root blockers retained. No target/sign/edit/compile/install/root/credential/IPC/auth/power/task/shipping credit;next own-code source plan needs new native scope.

**Latest: [binary DATA fake8/five-tool roundtrip reviewed PASS](../../docs/qa/macos-auth-v3-native-binary-data-01-result.md)** b8b67f5c5/scope1db950c8… consumed;34688B byte-identical DATA501:20/0600/noACL,never executed.2dirs/3files retained,closes checked. No root/compile/sign/install/IPC/auth/power/task/shipping credit;signature/loader/admission/privileged argv remain unqualified. Next requires new finite inspection scope.

**Latest: [native own-UID leaf6 reviewed PASS](../../docs/qa/macos-auth-v3-native-leaf-01-result.md)** b5030efa8/1clang+1UID501run/exits0,0/stderr0;actual native metadata/noACL/SHA/FD-name/root-refusal/close,2dirs/1DATA retained. Scope53509f56… consumed. Root traversal/admission/transport unqualified;no root/gate/install/explicit signing/IPC/auth/power/capsule execution/task/shipping credit.

**Latest: [native collector2build/fake8/default-deny reviewed PASS](../../docs/qa/macos-auth-v3-native-seed-collector-01-result.md)** bdeee1826/exits0,0,0,77/stderr0;scope9b78e812… consumed/builds-runs0. Artifact34688B/ff02642e… not root-admitted;native syscalls/self-origin/root dispatcher/transport unqualified. No root/fixture/install/explicit signing/IPC/auth/power/task/shipping credit.

**Latest: [separate native-seed QA policy fake8 PASS](../../docs/qa/macos-auth-v3-native-seed-policy-01-result.md).** QA-only path-based administrative assumption accepted,not FD-atomic;capsule contracts unchanged. fd138231…/cd8cd787…/scope4b1c9550… consumed. No native observer/privileged transport/actual OS receipt implemented;no native/build/sign/install/root/IPC/power/task/G1/G2/G3/shipping credit.

**Latest source-only: [local bootstrap NO-GO with current contracts](../../docs/design/baseline-ack-v2/local-native-bootstrap-trust-cut-2026-10-27.md).** Trusted first privileged actor/independent root receipt producer still missing. Preparation PASS retained; no new tests/build/root/task completion. A native administrative trust-seed design is not approved execution or changed admission policy.

**Latest: [NEW owner packetv2 fake24+DATA export reviewed PASS](../../docs/qa/macos-auth-v3-owner-packet-v2-01-result.md).**Only helper sentinel changed/new snapshot;prior failure retained.41623B non-executable JSON/1c1f83d4…/501:20/0600 PREPARATION_ONLY. baa30ea5… consumed,episodes/fakes0. Root executor/privilege transport/independent FD-ACL receipt absent;no native/sudo/root/sign/build/arming/QA/auth/power/task/G1/G2/G3/shipping credit. Actual root action needs separate attended owner scope.

**Latest: [owner packet phase HALTED episode2 test-helper failure](../../docs/qa/macos-auth-v3-owner-packet-episode2-01-result.md).**20/24 ran:19pass/1fail/4notrun,no package exported;helperNone->validSHA ambiguity,not demonstrated parser bug. Both episodes consumed/no repair/retry;episode1PASS24 preserved. No native/sudo/root/publication/sign/build/arming/QA/auth/power/task/G1/G2/G3/shipping credit;new attempt needs fresh scope.

**Latest: [owner literal DATA contract fake8 reviewed PASS](../../docs/qa/macos-auth-v3-owner-data-contract-fakes-01-result.md).**New defaultOFF QA namespace/abstract plan/native publisherNone,no real root/launcher/FD-ACL producer/durability/interpretation authority.850f67cf… consumed,episodes/fakes0;no native/publication/root/sign/build/arming/capsule/QA/auth/power/task/G1/G2/G3/shipping credit.

**Latest: [literal DATA01 UID501 roundtrip reviewed complete](../../docs/qa/macos-auth-v3-literal-data-transport-01-result.md).**Fake6 PASS/4 tools0/2 dirs,37523B raw exact/501:20/0600/root-refused. fb6c46c1… consumed,tools/episodes0. [Owner DATA trial contract DRAFT](../../docs/design/baseline-ack-v2/owner-literal-data-placement-contract-draft-2026-10-27.md) source-only/old pinned-FD contract current;no root publisher/sign/build/arming/link/FIFO/capsule/QA/auth/power/task/G1/G2/G3/shipping credit.

**Latest: [bounded DD01 UID501 reviewed complete](../../docs/qa/macos-auth-v3-bounded-data-copy-01-result.md).**Fake8 PASS/4 tools0/3 dirs,exact capsule +declared128KiB capped refusal;1227a296… consumed,tools/episodes0. [Literal DATA candidate](../../docs/design/baseline-ack-v2/literal-data-publication-candidate-2026-10-27.md) source-only/fake6 NOT RUN,no plutil execution or root publisher. No source-kind/liveness/root/sign/build/arming/link/FIFO/capsule/QA/auth/power/task/G1/G2/G3/shipping credit.

**Latest: [DATA tools01 UID501 reviewed complete](../../docs/qa/macos-auth-v3-data-publication-tools-01-result.md).**Fake12 PASS/6 commands0/4 dirs/3 byte-exact copies,actualUID501 root-refused. Same-UID source FD advanced EOF;install replaced sacrificial existing target. No privilege-transition/exclusive-source-kind/byte-cap/liveness/root qualification.076c971c… consumed,tools/episodes0;publisherNone/no root/sign/build/arming/capsule/QA/auth/power/task/G1/G2/G3/shipping credit.

**Latest: [native Apple API UID501 sequence reviewed observed](../../docs/qa/macos-auth-v3-apple-api-uid501-01-result.md).**Fake18 PASS/ONE probe0,TWO native anchorApple+strict validations OSStatus0;not root/path-to-FD atomic/closure proof. Scopeb05e476f… consumed,episodes/probes0. [Publication decision memo](../../docs/design/baseline-ack-v2/first-publication-decision-2026-10-27.md) source-only,original pinned-FD contract current;no root/publisher/sign/arming/QA/auth/power/task/G1/G2/G3/shipping credit.

**Latest: [readonly capsule fake12 reviewed PASS](../../docs/qa/macos-auth-v3-protected-origin-capsule-fakes-01-result.md),295f9c56…/47cec225….**37523B capsule entryNone/native ABI unqualified;UID501 counterpart source only,original root guard intact.0d57010f… consumed,new qualification needs finite authority. No native/root/staging/launch/task/G1/G2/G3/shipping credit or publisher.

**Latest: [QA env NEW attempt02 synthetic27 reviewed PASS](../../docs/qa/macos-auth-v3-qa-env-contract-fakes-02-result.md).**Strict15+QA12/source unchanged,inventory literal fixed in new runner/output;01 refusal preserved.625afb48… consumed,episodes/fake calls0. QA profile default-OFF/native factoryNone,old strict review unchanged. No native probe/root/sign/arming/QA/auth/power/task/G1/G2/G3/shipping credit;protected native producer/first publication still missing.

**Latest: [QA env contract01 preflight REFUSED,zero tests](../../docs/qa/macos-auth-v3-qa-env-contract-fakes-01-result.md).**Runner inventory filename mismatch;FileNotFoundError/exit3,27 bodies NOT RUN. Contract default-OFF/unqualified,f1bad45c… consumed,no repair/retry. No native probe/root/sign/arming/QA/auth/power/task/G1/G2/G3/shipping credit;fresh authority required for new fake attempt.

**Latest: [native environment01 reviewed complete](../../docs/qa/macos-auth-v3-native-environment-01-result.md).**Fake12 PASS/ONE nativeUID501 probe0,5456B own-task copies;extra CF key in two native snapshots matches Python mapping. No setter/startup/atomic/root proof;old exact-env review WITHHELD,policy unchanged.825b764d… consumed,episodes/probes0. No root/inspector/build/sign/arming/fixtures/QA/auth/power/task/G1/G2/G3/shipping credit.

**Latest: [environment differential01 completed](../../docs/qa/macos-auth-v3-clt-environment-01-result.md),[cache interpretation addendum](../../docs/research/clt-environment-observation-limits-2026-10-27.md).**Fake10 PASS/TWO CLT probes0;CF field present AFTER sys/os,only Python os.environ cached mapping equality observed,NOT native libc environment invariance. Prior observer review WITHHELD,no policy relaxation;frozen results unchanged. bb5c8f9f… consumed,episodes/probes0,no root/inspector/build/sign/arming/fixtures/QA/auth/power/task/G1/G2/G3/shipping credit.

**Latest: [observer01 diagnostic0,environment review WITHHELD](../../docs/qa/macos-auth-v3-origin-observer-01-result.md).**16 fakes PASS/ONE actualUID501 probe0;1818 nodes/FD-ACL/current9 CLT images+48 modules bound. Extra child __CF_USER_TEXT_ENCODING refuses exact-env acceptance,cause unproven,no relax/retry.5ee7e177… consumed,episodes/probes0;protected factoryNone. No root/build/sign/arming/fixtures/QA/auth/power/task/G1/G2/G3/shipping credit;new execution needs bounded authority.

**Services phase FINISHED:** [signature01 fake14+3 static source checks reviewed PASS](../../docs/qa/macos-auth-v3-stage-signature-01-result.md);[origin01 synthetic29 reviewed PASS](../../docs/qa/macos-auth-v3-stage-origin-fakes-01-result.md),c9de22ee…. Both episodes consumed/inspectors0;unused fake call cannot create third. Native factoriesNone,actual protected observer/first publication/root dispatcher absent;no ACL/root/sign/arming/QA/auth/power/task/G1/G2/G3/shipping credit. New execution requires bounded owner authority.

**Latest: [FD leaf filesystem01 fake50+REAL16 REVIEWED PASS](../../docs/qa/macos-auth-v3-stage-fdio-filesystem-01-result.md).**16 retainedUID501 trees/actual FD+ACL+mode+link+fsync/root-policy denial,no normalization.48ebc13d… consumed,nativeFactoryNone;protected services/root dispatcher/first publication remain missing. Source324/parent323/signedQA preserved;no root/sign/inspector/probe/arming/QA/auth/power/task/G1/G2/G3/shipping authority.

**Latest: [FD adapter01 exact46 SYNTHETIC PASS](../../docs/qa/macos-auth-v3-stage-fdio-fakes-01-result.md),not native/root qualification.**29 policy+17 new FD bodies;ca29ca19… consumed. Native gateNone,real OS/signature/origin services unexecuted/unwired. Resumed episodes exhausted;no real UID501 filesystem fixture/root/signing/probe/QA/auth/power or task/G1/G2/G3/shipping authority. SignedQA/source324/parent323 preserved.

**SOURCE ONLY:** [owner-selected QA-only CLT profile d8244f05…](../../docs/qa/macos-auth-v3-qa-clt-profile-source-2026-10-27.md),29 fakes NOT RUN(18 old+11 new),default branchdisabled/not immutable OS. No native backend/root launcher/production change/root/test-budget restoration/signing/arming/QA launch/auth/power or task/G1/G2/G3/shipping credit.

**Latest: [complete NONROOT mainimage01 reviewed](../../docs/qa/macos-auth-v3-clt-mainimage-01-result.md),not root clearance.**10 fakes/3 inspectors+1 NEW UID501 probe0;1818 stable nodes,13/13 CLT images+68 modules covered. Apple actualappverify0/flags0x0 NOT hardened;scope63c0947c… consumed,prior incomplete CLT01 preserved. Root trust-profile decision pending;no root/sign/arming/QA target/auth/power/task/G1/G2/G3/shipping credit.

**Latest: [CLT01 diagnostic0,bootstrap coverage REFUSED](../../docs/qa/macos-auth-v3-clt-bootstrap-01-result.md).**10 fakes PASS/6 inspectors+1 probe0;actual mapped Python.app main absent from manifest(12/13 CLT images covered).Scopef559d5db… consumed,phase inspector/probe budgets exhausted;FURTHER EXECUTION HALTED pending new owner scope. No root/sign/arming/QA target/auth/power/task/G1/G2/G3/shipping credit.

**Latest: [stage model01 exact18 fakes PASS](../../docs/qa/macos-auth-v3-root-storage-stage-fakes-01-result.md),not native stage.** Scope352e615a… consumed,no subprocess/compiler/root/target launch;image/source324/parent323 preserved. Xcode origin blocked;CLT alternative metadata-only/unqualified. No native backend/root launcher or task/G1/G2/G3/shipping credit.

**Latest: [QA image01 static build/repath/sign verification PASS](../../docs/qa/macos-auth-v3-root-storage-qa-image-01-result.md),ROOT NO-GO.**17 fakes/7 commands0/warnings0;source324/parent323 exact. New storage-QA-only define ON,production OFF;18 OS-location declarations/sole /usr/lib/swift RPATH,ad-hoc runtime/empty entitlements. No target/root launch;scope0de37bdf… consumed. Owner0500 image is not immutable root staging,task/G1/G2/G3/physical/expiry/shipping credit.

**Latest diagnostic:** [loader01 complete,three RPATH blockers/root NO-GO](../../docs/qa/macos-auth-v3-root-storage-loader-01-result.md),15 synthetic tests PASS,39 commands/18 OS-location direct library declarations. Scope8d016f24… consumed;no new build/arming/signing/root/target launch. Source323/130-test PASS unchanged;no task/G1/G2/G3/shipping credit.

**Latest: root-storage source01 UNARMED130 selected bodies+9 runner fakes PASS.**
[Result](../../docs/qa/macos-auth-v3-root-storage-inert-01-result.md):2 Debug commands0,
warnings0,110 fake+20 own-filesystem,zero direct fixture/root launches/no arming flag.
323 inputs/319 parent exact,23 trees retained,scope4062bfb8… consumed. Both gates OFF;
root walker only compiled. No root/enrollment/auth/installed IPC/power/expiry/physical/
restoration/G1/G2/G3/task/shipping completion from selected nonroot source qualification.

**Latest: root-storage source prepared, UNCOMPILED/new tests NOT RUN.**
[Scope4062bfb8…](../../docs/qa/macos-auth-v3-root-storage-source-2026-10-26.md):new323
inputs,parent319 intact;QA compile gate OFF/production gate OFF.11 new fake tests,unchanged
119 bodies;proposed ordinary-user130 selected tests plus9 runner fakes,2 UNARMED Debug
commands,no direct binary/root/auth/power execution or task/G1/G2/G3/shipping credit.

**Latest: process01 selected119 tests+10 children PASS, not whole-feature qualification.**
[Result](../../docs/qa/macos-auth-v3-process-inert-01-result.md):15 runner fakes,2 Debug
commands0/warnings0;119 Swift bodies+10 owned processes,exact busy75/pending76/self-exit73/
74 sequence.319 source/316 parent exact;4+23 trees retained,scope52555a17… consumed.
Production gates OFF;no task/G1/G2/G3/root/enrollment/auth/installed IPC/power/hardware/
independent expiry/physical restoration/shipping credit from nonroot process fixture success.

**Latest: process fixture source prepared, UNCOMPILED/NOT RUN/no new qualification.**
[New scope](../../docs/qa/macos-auth-v3-process-source-2026-10-26.md)52555a17… not approved:
NEW319 inputs,parent316 preserved;Debug-only test executable/no production library change.
Proposed15 runner fakes+2 commands(build/119 test bodies)+10 child launches (2 deliberate
self-_exit73/74). Source-only, no parent signals/root/auth/installed IPC/power or task/G1/
G2/G3/shipping completion. Filesystem04 selected119 PASS is not process-crash qualification.

**Latest: filesystem04 selected Debug119 PASS; whole feature still NOT qualified.**
[Reviewed result](../../docs/qa/macos-auth-v3-filesystem-inert-04-result.md):9 runner
fakes+99 fake/20 real UID501 filesystem bodies PASS,warnings0,result e5b5f054…;316 source/
315 parent exact,23 fixtures retained,scope02d34c8b… consumed. Actual file/directory ACL
rejection tested;01/02/03 failures stay historical failures. Root/traversal/provisioning/
auth/installed IPC/power/process crash/expiry/restoration/shipping unqualified,gate OFF.
No full-feature/task/G1/G2/G3 completion from selected nonroot fixture tests.

**Latest: filesystem03 compiled,117 PASS/2 fixture ACL errors; overall FAILED.**
[Review](../../docs/qa/macos-auth-v3-filesystem-inert-03-result.md):99 fake+18 filesystem
PASS,2 setupEINVAL22;119 started/compiler warnings0.315 inputs/23 trees preserved,scope
cdf0520f… consumed. NEW316-file [v4 proposal](../../docs/qa/macos-auth-v3-filesystem-v4-source-2026-10-26.md)
02d34c8b… not approved:tag before qualifier, granular errors,04 path only.Production/test
bodies unchanged/gate OFF. No task/G1/G2/G3/root/auth/power/ACL-rejection/shipping credit.

**Latest: filesystem02 test-macro compile FAILED; v3 test-only correction NOT RUN.**
[Failure](../../docs/qa/macos-auth-v3-filesystem-inert-02-result.md):compiler1/zero Swift
bodies,9 runner fakes PASS,scopea9ed8a76… consumed. NEW315-file
[v3 scope](../../docs/qa/macos-auth-v3-filesystem-v3-source-2026-10-26.md)cdf0520f… not
approved:throwing reads hoisted outside SAME test assertions, exclusive03 path, production
gate OFF/unchanged. No new compile/tests, filesystem PASS or task/G1/G2/G3/root/auth/power
credit. Original01/02 failures and prior99/131 PASS preserved separately.

**Latest: filesystem01 compile FAILED before tests; v2 correction source-only.**
[Failure](../../docs/qa/macos-auth-v3-filesystem-inert-01-result.md):mbr_uid_to_uuid not
in scope, compiler1/zero Swift bodies.9 runner fakes passed; scope67002446… consumed.
NEW314-file [v2 proposal](../../docs/qa/macos-auth-v3-filesystem-v2-source-2026-10-26.md)
preserves failed313, changes only test-support explicit import +new02 path; production
unchanged/gate OFF. Scopea9ed8a76… awaiting119-test approval, NOT RUN. No runtime storage,
root/auth/physical/shipping/task/G1/G2/G3 credit; previous99/131 PASS remains separate.

**Latest: filesystem fixture SOURCE prepared, no new executable verification.**
[Source +new119-test proposal](../../docs/qa/macos-auth-v3-filesystem-source-2026-10-26.md):
NEW313-file snapshot/parent310 preserved; internal nonroot FD fixture, truthfully owned
snapshots rejected by root validator, gate OFF.20 real filesystem test declarations NOT
RUN. Scope67002446… not approved; proposed9 runner fakes+one Debug119-test command includes
owned-directory ACL/mode/link/fsync/rename. No root/auth/IPC/power or task/G1/G2/G3 credit.

**Latest: storage selected Debug99 PASS, not native/whole-feature qualification.**
[Reviewed storage result](../../docs/qa/macos-auth-v3-storage-inert-01-result.md):9 runner
fakes+99 helper tests PASS/warnings0; source310/parent306 unchanged, gate OFF. Scopee8d21c7a…
consumed. Native storage code compiles but actual Darwin FD/ACL/flock/fsync paths unexecuted;
root provisioning/enrollment/auth UI/clock/nonce/main/native IPC/power remain unqualified or
unfinished. No G1/G2/G3/task/shipping completion; prior integration131 PASS stays distinct.

**Latest: integration selected Debug131 PASS; storage adapter source-only, native NO-GO.**
[Reviewed result](../../docs/qa/macos-auth-v3-integration-inert-01-result.md):9 runner
fakes+82 helper/49 client PASS/warnings0; scope0e1459f6… consumed, source306 unchanged.
NEW310-file [storage proposal](../../docs/qa/macos-auth-v3-storage-source-2026-10-26.md)
preserves306 and adds source-only publication/native adapter/17 tests (NOT RUN). Gate OFF;
new scopee8d21c7a… not approved. No task/G1/G2/G3 credit from fake IO; root provisioning,
actual filesystem durability/authentication/identity/power/physical/shipping unqualified.

**Latest: v3 integration SOURCE complete, not compiled/tested/deployed or qualified.**
[Source report +new inert proposal](../../docs/qa/macos-auth-v3-integration-source-2026-10-26.md):
new306-file snapshot/parent292 preserved, five shared-file edits +14 additions; wire/proof/
root-record policy/driver actual service guards written.131 selected declarations NOT RUN;
gate OFF, native FS/enrollment/UI still missing. Scope0e1459f6… awaits specific execution
approval. No task/G1/G2/G3 credit, compile/auth/keychain/root/installed IPC/power action.

**Latest: v3 source-slice Debug/selected fake tests PASS, NOT whole-feature completion.**
[Reviewed result](../../docs/qa/macos-auth-v3-first-slice-inert-01-result.md):9 runner fakes,
16 helper/7 client Swift tests/warnings0, two commands0/no uncertainty. Native gate OFF,
292 bound/original286 inputs unchanged; scope8c11d725… consumed. Native NO-GO; no live
codec/store/enrollment/driver/UI/key/auth/root/IPC/power or qualification credit. Full
suites/Release unrun; no task/G1/G2/G3 completion claimed from partial-module tests.

**Latest: v3 first code/test SOURCE slice only; uncompiled, not tested or qualified.**
Owner approved writes, NOT execution. [Snapshot/report/next inert proposal](../../docs/qa/macos-auth-v3-source-slice-2026-10-26.md):
286 copied inputs unchanged, five Swift additions/23 declarations NOT RUN; native adapters
OFF and live driver/wire/enrollment/root store unwired. Nil runner/nine fake tests not run.
No compile/auth/keychain/root/XPC/power/G1/G2/G3. New compile/capture approval required;
no whole-feature task marked complete and no reuse of consumed maintenance.

**Latest: macOS authentication RESEARCH/design complete, not implemented/qualified.**
Owner selected research BEFORE CODE. [Apple-source v3 delta](../../docs/research/macos-authenticated-baseline-ack-2026-10-26.md)
proposes persisted-right challenge signing with trusted root enrollment, separate finite lab
grant and24 extra PLANNED/NOT RUN scenarios. Additional RPC/new requested wait budget need
new scope. No old v2 source/doc/capture edits, keychain/auth prompt/compile/root/native action,
completed task or G1/G2/G3 credit. Review enrollment assurance before isolated implementation.

**Latest: OFFLINE ACK design complete, NOT implementation or qualification.**
[Contract](../../docs/design/baseline-ack-v2/contract.md), [change map](../../docs/design/baseline-ack-v2/change-map.md),
[56 planned NOT RUN rows](../../docs/design/baseline-ack-v2/test-matrix.md). Owner approved
DESIGN ONLY; lab root-grant proposal not human-consent proof, product rearm or runtime
acceptance. No current source/gate/signature/root/XPC/native changes or test/G1/G2/G3 credit.
Native NO-GO; future implementation and each executable/native stage need separate review.

**Latest: v27dd6dcdc… policy REFUSED despite safety PASS; scope consumed/NATIVE NO-GO.**
No backup/locks/unlink/pin/lifecycle/IPC/lease; all stderr0/no signals/unknown. [Guard trace](../../docs/qa/thermal-mainthread-baseline-gate-alignment-2026-10-26.md)
finds helper admission ALSO true-only/no ACK request field, unlike pure product readiness.
No new task/native/G2/G3 credit, source/guard/build/root change or maintenance-only bypass.
Offline contract decision needed; all old await-owner launch instructions are chronology.

**Latest: ONE maintenance-v2 approved; await OWNER foreground action.**
[Approved v2/handoff](../../docs/qa/thermal-mainthread-postrestart-01-maintenance-v2-scope.md),
frozen scopee21233ed…/captureb5dd8495…/30 actual fake tests/launcher0612f728… syntax/
verify-only/three injected cases PASS. No actual root/safety/policy/lifecycle/mutation;
local namespace absent. Fresh actual guards still required, no task/G2/G3/Inspect/lease/
physical credit. Earlier declined/await-old-owner chronology below never permits replay.

**Current: maintenance2466d0db… safety onACfalse REFUSED; scope consumed.**
Nominal/open/fresh6.817ms/console501/external0 pass, no policy query/backup/locks/unlink/
pin/lifecycle/IPC/lease reached. [Offline replay/diagnosis](../../docs/qa/thermal-mainthread-postrestart-01-ac-refusal.md)
preserves guard; await owner supply context. No new read/root/retry/native/G2/G3/task
credit. Earlier approved/await-owner instructions below are consumed history, not authority.
Frozen scoped40ce4ea…/capture1e7864b4…/30 actual fake tests/new launcher38b01172…
syntax/verify-only/three injected cases PASS. [Owner handoff](../../docs/qa/preview-evidence/thermal-mainthread-postrestart-01-maintenance-approval/owner-handoff.md)
ONCE/no sudo-prefix/redirect/retry; no actual maintenance, new safety/policy query or
mutation attempted. Local namespace absent/protected attempt not queried. Historical
not-approved/read-handoff text below is chronology; no task/G2/G3/Inspect/lease credit.
Helper/plist/old pin bytes+inodes and exact prior-boot27bec…/rev9/restore/ack journal
retained, PID531 at capture. No mutation/lock/IPC/lifecycle/power; all stderr0.
[New nil maintenance scope](../../docs/qa/thermal-mainthread-postrestart-01-maintenance-scope.md)
source84bd8b25…/scoped40ce4ea…/30 fake tests keeps full fresh dev binding and all safety/
policy/lifecycle guards, requires new owner approval. No new task/G2/G3/ready/restoration
credit. Earlier ROOT-read await-owner instructions below are consumed chronology.
UID501 result8470fa1e…/taskb800fe079 completed0: boot845C2F70-315D-4214-BBD7-7BB934EC9FC1,
public policy(false,true,false) at capture/two children0/stderr0/no signals/unknown;
scope consumed, profile match NOT restoration/no-lease/ready. No task/G2/G3 credit.
[Approved ROOT audit/handoff](../../docs/qa/thermal-mainthread-postrestart-01-root-readonly-scope.md):
frozen scope48e192d9…/capture8bd88fb5…/19 actual fake tests/launcherfdc53dd5… syntax/
verify-only/three fake cases PASS; no actual root access. Owner must run ONCE; mutation/
IPC/lifecycle/lease pause stays. No old launcher replay or new native qualification.

**Latest actual failure:** thermal baseline97ec6c6d…/taskba1952455 failed3 despite client0/
protocol cleanupAcknowledged: retained complete65540B stderr =580 Swift MainActor off-main
warnings at ShortSleepQA/main.swift:21. A/B consumed, latches retained/rechecked; no root/
lifecycle/Stop/kill/restoration/G2 or new task completion. Current policy/journal/lease absence
unknown. [Isolated runloop proposal](../../docs/qa/thermal-mainthread-inert-reproduction-scope-2026-10-24.md)
map5eca77ef…/one-file patch. First approved inert batch failed935087cd… at compiler1/
stdlib lookup, zero probes/matrix; consumed/no replay. [SDK-v2 proposal](../../docs/qa/thermal-mainthread-sdk-v2-scope-2026-10-24.md)
SDK-v2 also failed97200c23… at fixture MainActor initializer/one compiler/zero probes or
matrix; both scopes consumed. [Fresh actor-v3](../../docs/qa/thermal-mainthread-actor-v3-scope-2026-10-24.md)
actual84306e02… PASS: dispatch3 ticks/Stop off process main, run-loop all6 events/main;
production warning not reproduced. Matrix4f272f6f…/122 each/CLI13 each/Python7/exclusions7/
warnings0; inert scope consumed, NOT native fix/restoration/qualification credit.
[App-only build/sign](../../docs/qa/thermal-mainthread-app-build-sign-scope-2026-10-24.md)
completed staticdab8bd6a…/one app build+sign/nine commands0/own diagnostics stderr0;
new appbb7ea02c…/freeze67e963e9…, helperAA/readiness unchanged. NOT installed/admitted/
native-qualified; build/sign scope consumed. [Current root audit](../../docs/qa/thermal-mainthread-current-root-readonly-scope-2026-10-24.md)
reader55659228…/capture24627ccb…/16 actual-capture fake tests, scope542adba2… approved;
launcher3ecfcfb9… syntax/verify-only/three injected cases PASS; await owner foreground
UID501 read completed0/receiptde485bcf…/outer+two query stderr0: exact thermal payloads/
PID85822, current journal27bec47b…/474B/inode3476418/rev9 restoreLidPolicy acknowledged.
Read scope consumed, NOT native ready/lease absence/restoration/qualification. [New exact maintenance](../../docs/qa/thermal-mainthread-exact-journal-client-repin-scope-2026-10-24.md)
source4f8e6599…/capture00bd42a7…/26 actual-capture tests, scope66dc04ba… approved;
launcher1124a744… syntax/verify-only/three injected cases PASS; await owner foreground
UID501 maintenance actualfc9a7583… exit3/preflight: nominal/nonthermal passed,
policy(false,false,false) refused at AppleClamshellCausesSleep; four children0/stderr0,
no backup/unlink/pin/lifecycle reached. Scope consumed/no replay. [Offline diagnosis](../../docs/qa/thermal-mainthread-policy-refusal-diagnosis-2026-10-24.md)
keeps guard unchanged; public false is not mask/owner/clear-failure proof. Owner selected
"Tạm dừng native (Recommended)": preserve staged client/system/evidence, no more native
query/clear/restart/pin/lifecycle/Inspect/lease. No new qualification/task-completion credit.
Old67/current signed74/proposed74 unchanged.
Historical chronology follows.

**Latest native protocol progress:** new thermal Inspectd7b4fcf4…/taskb4a503cbf completed0,
ready/noPendingIntent/mutation=false/token absent; three processes0/stderr0/original latch
retained/rechecked. Scope consumed/no lease/root/lifecycle/restoration/G2 or new task completion.
[Separate A/B baseline proposal](../../docs/qa/thermal-policy-lid-open-baseline-scope-2026-10-24.md)
source62806235…/58 offline tests/both nil; one NEW Inspect then distinct conditional60s run
and explicit private-stderr permission required. No new native call; older pending labels
below are historical and never replay authority.

**Latest completed deployment:** owner installf4bf1c2c… exit0/outer stderr0/newPID85822;
new helper+pins published/bootstrap1/bootout1/three exact113 barriers, no IPC/lease. Scope
consumed; source-enforced original locks/no journal/plist preserved, not live ready/restoration.
[Fresh Inspect proposal](../../docs/qa/thermal-policy-fresh-inspect-scope-2026-10-24.md) nil/34
offline tests/run=false; finite-child Stop/no-kill guard/root context reviewed. No new native
read/Inspect or G2/G3 task completion. Historical pending labels below are not replay authority.

**Latest thermal deployment boundary:** new74-input app/helper/readiness static sign PASS
result13d2d462… (app66353feb…/helperaa2b65fe…), not installed. Owner root-read result839a41cd…
reviewed: old payloads/original locks/no journal/PID17056 at capture; scope consumed, no ready/
restoration/lease-absence inference. [New helper+pin/lifecycle proposal](../../docs/qa/thermal-policy-helper-install-scope-2026-10-24.md)
source247e1b8a…/22+37 fake regressions PASS; now separately approved scope7afad9e2…/
capture71a5104e…/launcherec9f504b…/22 actual-capture+3 injected launcher tests PASS.
Owner foreground Terminal credential action pending/output absent. No root
mutation/Inspect/lease/new implementation task or G2/G3 completion credit. Historical chronology follows.

**Current M9 boundary:** owner archivalfdbec0db… completed0/stderr0/exact rev9 archived,
original locks/pins preserved, bootout1/bootstrap1/three113/newPID17056 at capture; scope
consumed/not live ready/restoration. [Two next scopes](../../docs/qa/m9-after-retirement-inspect-diagnostic-scope-2026-10-24.md)
template nil/42 fake tests/signed67 unchanged. Owner separately approved A Inspect/B60s+
private stderr; capture6ee0fa40…/launcher3587f2c7… syntax/verify-only/11 actual-capture fake
tests PASS. Owner attempted:65c437db… refusedinitialSafety/onAC=false only, Inspect0/run0,
sole QA readiness0/stderr0/no IPC/lease/root/lifecycle. Both scopes consumed/private raw
stderr absent/no replay. New comparisonbd85d0f6… pmsetAC/QAtrue agree/seven checks pass,
read consumed. [Attempt2](../../docs/qa/m9-after-retirement-diagnostic-v2-scope-2026-10-24.md)
namespace-only/42 fake tests/signed67 unchanged; fresh A/B now separately approved.
Captureee4de156…/launcherddc24bd5… syntax/verify-only/11 actual-capture fake tests PASS.
Owner attempt2f85910f2… refusedinitialSafety/onACfalse only/Inspect0/run0/no IPC/lease/
root/lifecycle; both scopes consumed/private raw absent/no replay. [Read-only diagnosis](../../docs/qa/m9-repeated-ac-refusal-readonly-diagnosis-2026-10-24.md):
pause actuation/projection3+nil observer6 PASS. Same-Terminal read separately approved:
capture63a51ae8…/launcherc9fc3836… actual-capture6+syntax/verify-only PASS. Owner Terminal
read completed:cfe0e7f1… three commands0/stderr0/pmsetAC+QAtrue/seven checks pass/read
consumed/cause not reproduced. Owner reports source changes/no charge-control app;
conditions differed/exact cause unproved/no code patch. Owner now separately approved
[v3 A/B](../../docs/qa/m9-after-retirement-diagnostic-v3-scope-2026-10-24.md): namespace-only/
42+11 fake tests/signed67 unchanged/capturee65bd9e0…/launcher9b4fccea… syntax/verify-only
PASS. Actual v3 result574391ba… refusedinitialSafety/thermalNominalfalse only/ACtrue/
Inspect0/run0/no lease/IPC/root/lifecycle; both scopes consumed/private raw absent/signed67
unchanged. Pause/cooling/no replay/new diagnostic authority/task/G2 credit.
NEW SOURCE TRACK: owner chose fair allowed/serious>=30s stop/critical on observation;
[new isolated candidate](../../docs/qa/thermal-policy-serious30-critical-candidate-2026-10-24.md)
78 offline tests PASS (helper62/selectedQA10/parser6), original277/frozen67 unchanged;
10-file patch verified in temporary baseline. Not merged into original source/signed/
deployed/active; no native runtime or G2/G3 credit.

**Historical pre-maintenance boundary:** owner audit cf1b6c15… completed0/stderr0/final payloads/original
locks matched/PID75560 at capture; journal707db730… revision9 restore/ack, not ready or
restoration. Read consumed. [Exact archival proposal](../../docs/qa/m9-exact-revision9-retirement-scope-2026-10-24.md)
template nil/26 fake tests/signed67 unchanged; maintenance separately approved only,
capture1a60e845…/launcher7ed4b189… syntax/verify-only/15 actual-capture fake tests PASS.
Owner ordinary Terminal pending/output absent; no journal removal/lifecycle/Inspect/lease/
task or G2 credit.

**New offline preparation:** [full thermal/Celsius diagnostic](../../docs/qa/m9-full-thermal-diagnostic-scope-2026-10-22.md),
12 fake tests PASS; exact sensor/model/clock reuse; build/sign/pure self-test b8e516cd5
passed, warnings0. V1 preparation refused64KiB source cap on125776B executable before
native dispatch/intent. [V2 observer](../../docs/qa/m9-full-thermal-v2-read-scope-2026-10-22.md)
nil/10 tests PASS/same signed binary, source cap unchanged; owner read b79faa52b
completed0: CPU die63.6°C/OS before+after nominal, QA AC/all seven PASS at capture,
result1838d6e6…. Read consumed/no root/IPC/lease. [Fresh continuation v2](../../docs/qa/m9-final-continuation-v2-scope-2026-10-22.md)
templates nil/post-consent32 actual-capture tests PASS; owner separately approved A/B,
capturesce3f79ab…/1c78d034…/4d9e3add…/Terminal launcher verified without root/native query.
Owner v2 completed rootac61a01e… exit0/zero bootout/bootstrap1/newPID75560 at capture;
Inspect ready, actual acquire+5renew active, releasefalse/cleanupAck/finishedAck/client0.
Baseline3b5b3160… refused65540B stderr, raw content unknown; three offline projections
confirm guard. Both scopes consumed/no re-run/Inspect/lifecycle/reset. [New passive policy read](../../docs/qa/m9-first-real-baseline-stderr-policy-scope-2026-10-22.md)
owner approved/completed b4c121364, result574fb275…: SleepDisabled=true,
AppleClamshellCausesSleep=true/lid open; cause/ownership/restoration unknown, read consumed.
No new root/IPC/lifecycle/power/log query. Need fresh read-only configuration/assertion
attribution approved bc45b2c71/completed0/resultb31c6d1c…: systemWide SleepDisabled1,
lidwalkd/PID359 idle assertion, no setter/app mapping proof. Owner reports another app,
initially named LidWalk; owner confirmed discovered LidRun/com.lidrun.app. CLI b6281ec6e/
e1f85bea… already Awake Off/both flagsfalse before/after, zero Stop. Authorized follow-up
b52a14170/b58c810b… still SleepDisabled=true/CausesSleep=true/lid-open; no induced change/
setter/restoration proof. Read consumed; fresh scope for further native attribution/repair,
no forced clear/daemon kill. Signed67/no G2/task credit unchanged.

**Latest:** actual development LidWalk in cam-lid-v2, distinct from installed LidRun:
owner disabled Close Lid; separately approved ordinary Stop baa2675e9/bc6f2e0c… confirms
live keepAwake=false/displayAwake=false/sleepPolicy=off. No CamLid retest. [Private stderr
preparation](../../docs/qa/m9-private-stderr-diagnostic-preparation-2026-10-24.md) nil/21 fake
tests PASS/original guard/signed67 unchanged. Fresh helper/journal diagnostic scope needed
before any ready Inspect/run; no implicit restart/deletion/repair or task credit.

**Current M9 execution boundary:** thermal root preflight refused before backup/lifecycle;
subsequent safety b6250ce5e passed at capture, not admission. Owner “Làm đi” requests
[fresh same-bounds v2 lifecycle + conditional baseline](../../docs/qa/m9-final-helper-restart-v2-scope-2026-10-22.md).
Namespace-only captures/19 fake tests/Terminal verify-only PASS. Owner v2 then reached
protected backup/bootout0/first print0; parser refused before absence/locks/bootstrap/lease.
Exact1000B stderr hash identifies unexpected service fields, raw field Unknown. Scopes
consumed; [new passive audit](../../docs/qa/m9-after-restart-v2-partial-readonly-scope-2026-10-22.md)
7 tests PASS/template nil; owner granted one passive audit, capture01a6177c…/Terminal
launcher verified; owner audit completed0/stderr0: absentAtCapture/print113, final
payloads/no journal/original locks/all four v2 ledger files match, scope consumed.
[New zero-bootout continuation](../../docs/qa/m9-final-helper-absent-continuation-scope-2026-10-22.md)
11 root/8 conditional sequence tests PASS/templates nil; owner separately approved
continuation and baseline, captures1784cd93…/8f04369e…/sequence0427161f…/Terminal launcher
verified offline; owner attempt refused at preflight: only onAC=false,
other six checks passed/fresh30.117ms. No service print/locks/new protected context/
bootstrap/IPC/B/lease; both scopes consumed/no retry. Result dd50b1f9…, signed67 unchanged.
New separately approved safety b2b47892f completed0/commands0/stderr0: onAC=false
still sole failure/thermal nominal/fresh27.769ms. Read consumed; no root/IPC/bootstrap/
lease/resume. Result a81bb180…; owner check Battery menu Power Adapter/cable/adapter/
port/outlet. Owner reports connected; new approved three-read comparison b13f92893
completed0: macOS AC/QAonAC=true agree, thermalNominal=false sole blocker/fresh8.948ms,
severity unknown. Result1aaf3379…; scope consumed/no root/IPC/bootstrap/lease/poll/resume.
New sample/attempt needs fresh scope; no G2/restoration/task-completion credit.


**Feature context:** `012-closed-lid-best-effort`
**Status:** Phase 0 offline complete (2026-10-19). The model, readiness projection, consent,
presentation and JSON contract are implemented with fake-only tests (51 tests in the package
pass). Native tasks below still require their own one-use approvals.
**Source:** [spec.md](spec.md), [plan.md](plan.md), [decision memo](../../docs/planning/closed-lid-product-path-2026-10-19.md).

## Phase 0 — Offline (no power, no service, no protected-path writes)

- [x] **T001 — Audit the clear/suppression path.**
  Read `LidSpecificMechanism`, `LeasePowerMechanism`, `PowerLeaseService.restore()`, the
  native selector binding and the v8/v9 receipts. Document what the selector does with
  `enabled: true/false`, what a successful clear receipt looks like, and whether any code path
  could explain the observed `AppleClamshellCausesSleep = No` after cleanup. Output: a short
  findings note appended to the plan or a new `docs/qa/` note. *Done when:* the R0 design has
  a named hypothesis and the exact receipt fields to capture.

- [x] **T002 — State model types.**
  Add `BestEffortSessionState` and `BestEffortClearEvidence` (working names) with unit tests
  covering every transition. No changes to `RestoreState`. *Done when:* exhaustive
  transition tests pass, including unknown clear/crash paths.

- [x] **T003 — Readiness projection.**
  Add the best-effort facts/projection with stable reason codes. Assert
  `ProtectionEffectiveState.protected` is unreachable for this backend. *Done when:* unit tests
  cover every precondition and the unreachable-protected test passes.

- [x] **T004 — Fake backend and fault injection.**
  Fake acquire/stop transport; inject journal commit failure, clear failure/unknown, release
  failure, lease expiry, app crash, helper crash, AC loss, thermal and foreign override.
  *Done when:* every case maps to a defined state and never silent-ready.
  *Offline result:* the existing `SimulatedLidSession` fakes cover journal/lease/assertion
  failures; the new product model covers clear partial/unknown/not-attempted, crash, sleep,
  boot reconciliation and readiness faults. No new transport abstraction until G3.

- [x] **T005 — Consent model and copy.**
  Versioned consent record, exact risk copy (crash/indefinite override, unverified restoration,
  hidden writers), revocation and re-consent rules. *Done when:* tests enforce consent before
  any start and re-consent on version change.

- [x] **T006 — UI projection and copy.**
  Banner, state labels, disabled reasons and recovery sheet copy; Settings experimental flag.
  No green shield/"Protected". *Done when:* snapshot/state tests cover every state and the
  forbidden-string test passes.

- [x] **T007 — CLI contract.**
  Status fields (mode, state, cap/lease remaining, clear evidence, recovery reason, consent
  version) and start/stop refusals behind the flag. *Done when:* GUI/CLI parity tests pass and
  no `protected`/`verified` key exists for the backend.

- [x] **T008 — Documentation links.**
  Link this spec from the roadmap M1 section, the proposal §7C and the decision memo.
  *Done when:* links resolve and the roadmap states M1 remains blocked until G1/G2/G3.

## Phase 1 — R0 native experiments (one-use approval per boot)

- [x] **T100 — R0 preparation (offline).** Pinned journal resets
  (`reset-r0-clear-episode-journal-qa.py`, `reset-r0-attempt2-clear-episode-journal-qa.py`,
  `reset-r0-attempt3-clear-episode-journal-qa.py`), open-lid session hold
  (`r0-session-hold.py`), post-cleanup observer (`observe-r0-post-cleanup-sleep.py`) and
  [runbook](../../docs/qa/r0-behavioural-clear-runbook-2026-10-19.md).
  *Done when:* self-tests and read-only preflights pass with no native action.
  *Result:* all self-tests pass; attempt #1 and #2 reset preflights passed on their fresh
  boots; each later reset correctly refuses on the consumed previous boot. Nothing actuated
  during preparation.

- [x] **T101 — R0 attempt #1.** Executed on boot `1002AE9A-…` with one-use approval. The v9
  recorder's close cue was missed (its 6 s window), so it aborted after acquire/renew and
  cleaned up (`cleanupAcknowledged/userStop`). The post-cleanup observer then closed the lid:
  `Clamshell Sleep` at 19:08:29, Wake 19:08:55, property `true` before close / `false` after
  wake. Result **`R0_POST_CLEANUP_SLEEP_OBSERVED`** — clear behaviourally effective; property
  stale after wake. Record: [attempt #1](../../docs/qa/r0-behavioural-clear-attempt1-2026-10-19.md).
  *Deviation:* no closed interval during the session (recorder mismatch), not a clear failure.

- [x] **T102 — R0 attempt #2** executed on boot `FD97CCAF-…`: reset the attempt #1 journal
  (`1002AE9A-…` / `2C31C3C6-…`), one open-lid session hold (active 10.42 s, lid open, no
  sleep/wake, exit 5, `cleanupAcknowledged/userStop`), then the observer. The observer's
  strict output was **`R0_POST_CLEANUP_NO_SLEEP`**, but the raw pmset log shows
  `Entering DarkWake state due to 'Clamshell Sleep'` at 19:32:41, `Display is turned off`,
  and a full wake at 19:33:22 on lid open. This is a **false negative** in the observer's
  classifier, not a suppression event. Record:
  [attempt #2 adjudication](../../docs/qa/r0-attempt2-adjudication-2026-10-19.md).
  *Deviation:* observer counted only `Entering Sleep state`; fixed to count clamshell
  DarkWake and store raw pmset lines; self-test passes.

- [x] **T103 — R0 adjudication and go/no-go.** Attempt #3 executed on boot `A9BC665D-…`:
  reset the attempt #2 journal; session hold clean (10.54 s, `cleanupAcknowledged/userStop`);
  observer retry #1 timed out at the Continue dialog; retry #2 closed the lid and the Mac
  produced a full `Clamshell Sleep` at 22:11:13 (display off 22:11:08), but the operator
  missed the spoken “Open now” cue and the observer wrote no `result.json`. Raw evidence is
  **`R0_POST_CLEANUP_SLEEP_OBSERVED` (full)**. Three-boot record: #1 full sleep, #2 clamshell
  DarkWake, #3 full sleep (raw). The owner accepted the raw #3 evidence on 2026-10-20; R0 is
  met for behavioural same-boot clear effectiveness. The observer's open cue is fixed to a
  visible dialog (self-test passes). No further native action on this boot; reboot. G2/G3
  still need separate approvals; M1 remains BLOCKED. Record:
  [attempt #3 adjudication](../../docs/qa/r0-attempt3-adjudication-2026-10-20.md) and
  [owner acceptance](../../docs/qa/r0-owner-acceptance-2026-10-20.md).
  *Done when:* the memo records the decision and the roadmap reflects it.

## Phase 2 — G2 native qualification (separate approvals per episode/boot)

- [x] **T201 — Full system Sleep repeats** (owner-frozen 2026-10-21: ≥3 across ≥2 boots): — **Review 2026-10-31:** closed as superseded: Strict is frozen (ADR 0001). The general need for a manual Sleep check moves to 014 T706.
  clean termination, zero unexplained darkwakes, operator attestation. Genuine backend
  failure under a valid procedure rejects the backend; invalid/incomplete attempts do not
  count as PASS or permit automatic retry. No native episode is approved by policy freeze.
  [M9 offline preparation](../../docs/qa/g2-m9-next-qualification-packet-2026-10-21.md) is ready;
  the owner separately approved and completed the state-specific
  [archival/bootstrap continuation](../../docs/qa/m9-stopped-daemon-continuation-packet-2026-10-21.md)
  and one real Inspect returned ready/noPendingIntent with mutationAttempted=false. Both
  scopes are consumed; readiness is capture-scoped, not future admission or restoration.
  A [pure timing-only layer](../../docs/qa/m9-manual-sleep-timing-draft-2026-10-21.md) has 14
  synthetic tests, 98 total hardware tests passing; initial review math/floor findings fixed,
  final static recheck closed with no scoped blocker. Historical v9 raw Sleep archives are
  absent here and do not count
  as independently verified M9 repetitions. No new native Sleep row, recovery or IPC scope
  is approved by preparation; T201 remains unchecked. The separately approved passive
  snapshot is consumed. A [lexical inventory](../../docs/qa/m9-power-log-lexical-inventory-2026-10-21.md)
  records 201 transitions/one opaque barrier after offline privacy correction, no historical
  G2 credit. Seven lexer tests bring the total to 105 passing; initial flag-output review
  finding fixed with red/green regression, final static recheck closed with no scoped blocker.
  Owner froze cue5s/intendedwake~8s/live>=30s/end<=55s design only. The
  [pure lifecycle-order draft](../../docs/qa/m9-manual-sleep-protocol-design-2026-10-21.md)
  adds 12 synthetic tests (117 hardware total passing), callback-order review finding fixed
  with red/green regressions, final static recheck closed. Owner chose a separate
  [short QA core offline](../../docs/qa/m9-short-sleep-qa-offline-candidate-2026-10-21.md);
  proposed60s/<=5renew/Stop58s/deadline61s with no native transport. Debug/Release fake/inert
  verification passed13 fake Swift tests each Debug/Release and14 inert CLI cases after
  actual runtime RED and fixes for release-ack/callback Stop; final core recheck closed.
  Eight fake driver/admission tests bring21 Swift tests each Debug/Release +14 inert CLI
  cases passing. Reentrant send review blocker reproduced with23-test runtimeRED; pending-ID
  fix now passes23 Swift tests each Debug/Release +14 inert CLI cases; final driver recheck
  closed. Compile-only XPC bridge now source-gated nil with no executable native entry;
  26 fake Swift tests each Debug/Release +18 inert CLI pass; bridge static review closed.
  Owner chose [external episode gate](../../docs/qa/m9-external-episode-gate-offline-2026-10-21.md)
  offline; validator/private-store compiled38 Debug tests but12 new fixture setups refused
  unsafeStorage. Diagnostic proved Foundation's `/var` alias; test-only realpath fixed,
  guards unchanged. Final-marker review race proved42-test runtime RED; post-context
  marker fd/name/path binding passes42 Swift tests each Debug/Release +18 inert CLI;
  tested source/binary hashes saved, final offline-store recheck closed. Provider seams
  inspected; context-builder hardened, admission ordering and self-only Security observation
  added,67 Swift tests each Debug/Release historically; latest
  [real-store composition](../../docs/qa/m9-short-sleep-store-composition-2026-10-21.md)
  now includes injected observations, bounded file/source-map evidence and self-reader
  clock-order regressions: latest completed run (2026-10-22) passes 93 inert tests plus
  14 CLI checks each Debug/Release, zero warnings (100 declarations, seven native self-read
  tests excluded). Scoped source/file reviews found no blocker. Extended expiry-during-
  digest/signature/boot composition passed: retained latch, zero transports. Historical approved helper-file
  SHA/CDHash matches M9; no running-peer authentication or native wiring. Preserved signed
  CLI predates fixes; no root trust decision follows. Subsequent
  [stage 1 native reader/provenance preparation](../../docs/qa/m9-native-admission-stage1-2026-10-22.md)
  now passes 104 inert Swift tests plus 22 CLI checks each Debug/Release, zero warnings,
  and six Python tests. An unsealed Release QA `.app` and the tested source map share 63
  unchanged local inputs. A subsequent approved copy/sign/self/provider batch passed signing
  and packaged self-identity but provider refused `insecureFile`, with no JSON. A separate
  metadata-only pass found a current deny-delete home ACL rejected by the blanket rule;
  corrected v2 now passes 107 inert Swift tests plus 22 CLI checks each Debug/Release, zero
  warnings, and six Python tests. New unsealed Release app and tests share 63 unchanged input
  hashes; 114 declarations, seven native tests excluded. Freshly approved v2 signing/self/
  provider batch PASS (`b6235bfe3`), app CDHash `9a83aff9e654dfb417a39a6e04ddcf99ffffa34d`;
  static identities/digests match independent freeze. One self/provider call; scope consumed.
  Read-only capture is not running-peer authentication. Root trust/lifecycle and IPC remain
  separately unapproved; no physical qualification or complete execution wiring follows.
  [Trust/lifecycle sequencing](../../docs/qa/m9-v2-trust-lifecycle-plan-2026-10-22.md) records
  owner-supplied journal absence/expected locks and a separately approved UID501 snapshot:
  older configured app pin, running best-effort daemon PID7145. Read scope consumed;
  ACLs/cached requirement/running peer/lease remain unqualified. Finish final client offline
  before selecting final root pins. Subsequent
  [final-runner source](../../docs/qa/m9-final-runner-offline-2026-10-22.md) is wired and inertly
  verified: 113 tests each Debug/Release, zero warnings, 22 total CLI checks, seven Python
  tests; 65 inputs bound. Enabled-build/signing still needs exact approval; default nil gate
  remains closed, no real episode/IPC or physical qualification. The 65-input runner's
  separately approved build/sign/read-only batch PASSed (`b43a5287d`), scope consumed, but
  pre-provisioning review found a missing lease-free Inspect route. Corrected
  [runner + Inspect](../../docs/qa/m9-runner-inspect-completion-2026-10-22.md) now passes
  122 tests per Debug/Release, zero warnings, 26 CLI checks and seven Python tests, 67 inputs
  bound. Separate operation scopes prevent Inspect-to-run promotion. Fresh signing approval
  was subsequently granted: batch `b872921f4` PASS, final app CDHash
  `04e2d6b3395aa4d4a1570ce87cd17e0b5ba2bbf2`, all 67 inputs matched; scope consumed.
  [Root-pin prerequisites](../../docs/qa/m9-final-root-pin-prerequisites-2026-10-22.md) prepared,
  not an executable mutation packet; current root evidence/lease/lifecycle review still needs
  separate scope. No root trust, live IPC, real episode or G2 physical row follows. Do not
  root-pin earlier intermediate images. Owner root audit then matched old baseline/ACL-free
  metadata; old-client one-Inspect `b62ab8da3` returned accepted/stopped/sleepObserved,
  mutation=false, not ready. Scope consumed, no retry. Actual-service fake regression PASS
  each Debug/Release; [stopped-helper pin/lifecycle packet](../../docs/qa/m9-stopped-helper-repin-packet-2026-10-22.md)
  prepared, 19 new + eight prior fake tests PASS, gate nil. Exact root approval required;
  no root mutation/restart/new-client IPC or physical acceptance follows. Owner later approved
  one exact root batch; its single Terminal attempt refused at initial fresh-safety guard,
  exit1/preflight/ValueError. [Offline diagnosis](../../docs/qa/m9-stopped-repin-preflight-refusal-2026-10-22.md)
  exactly matches stderr bytes/hash, but lost safety values leave the failed field unknown.
  Scope consumed; no pin write/lifecycle/retry. Separately approved UID501 read `b6e445a80`
  captured onAC=false as sole failed current check; [human power-source check required](../../docs/qa/m9-current-safety-observation-2026-10-22.md).
  Read scope consumed; current sample is not the lost root-refusal sample or new authority.
  After owner reconnected charger, separately approved independent `b51922215` captured
  onAC=true, thermalNominal=false as sole failed check (9ms), fresh intent/result retained.
  Human cooling/load check was needed; subsequent owner-requested `b950fb120` captured
  all seven checks passing (9ms), new intent/result, not root authority.
  [V2 diagnostic root proposal](../../docs/qa/m9-stopped-helper-repin-v2-scope-2026-10-22.md)
  prepared: red/green sample-loss regression +25 Python PASS, gate nil, new exact root
  approval was required; owner subsequently granted exact v2 scope. Captured `6dcfac83…`
  owner attempt then failed after bootout0/immediate print0, absence guard refused.
  Protected backup/intent written, no lock acquisition/pin rename/bootstrap. Scope consumed,
  no retry/rollback. [New read-only audit](../../docs/qa/m9-v2-bootout-failure-readonly-scope-2026-10-22.md)
  prepared, seven fake/owned-file tests PASS, gate nil. Owner granted exact read-only
  scope; owner audit completed0: service absentAtCapture/print113, old payloads/pins/v2
  ledger match, no journal/original locks retained (not acquired), no restoration/peer proof.
  [New stopped continuation](../../docs/qa/m9-after-v2-stopped-continuation-scope-2026-10-22.md)
  prepared, 42 tests PASS, template gate nil. Owner granted exact continuation scope;
  captured `65cf4c6d…`/new Terminal launcher verified without sudo/root observations,
  owner run completed0: final pin published/revalidated, zero bootout/one bootstrap0,
  four passing safety samples, job running PID50171. Scope consumed; not readiness/
  restoration/physical proof. [Final-candidate Inspect-only packet](../../docs/qa/m9-final-candidate-inspect-scope-2026-10-22.md)
  prepared, ten tests PASS, gate nil; fresh positive-IPC approval needed. Negative live-auth
  separate. Owner-approved b74a8ac01 then completed0: one admitted final Inspect, genuine
  record/latch match, ready/noPendingIntent/accepted=true/mutation=false/no token. Scope
  consumed, no lease/restoration/physical qualification. [Rejected-peer fixture build scope](../../docs/qa/m9-rejected-peer-fixture-build-scope-2026-10-22.md)
  prepared then separately approved build ba5e9b63d completed0: Swift6 zero diagnostics,
  hardened sign/verify/self-test/identity PASS, fixture CDHash8a9ab0b6…. No XPC entry.
  [Runtime proposal](../../docs/qa/m9-rejected-peer-runtime-scope-2026-10-22.md) five fake
  tests PASS/gate nil; owner approved one runtime bcff7f864, refused at safety/onAC=false,
  thermal nominal true. Zero fixture processes/negative IPC; scope consumed/no retry.
  Human actual-power-source check was needed; owner then approved independent b66d65e56,
  safety all seven pass, one actual fixture generic failure/exit3/stderr0, **auth inconclusive**.
  Scope consumed/no retry. [Filtered log proposal](../../docs/qa/m9-rejected-peer-log-readonly-scope-2026-10-22.md)
  approved be255332e completed0: eleven filtered records correlate fixture54860/helper50171,
  helper signing token but no sentence/rejection direction, auth remains Unknown.
  [Exact-message context scope](../../docs/qa/m9-rejection-context-read-scope-2026-10-22.md)
  approved bbe94d4f0 completed0, exact helper message matched but action/tail redacted,
  auth still Unknown. [V2 finite context proposal](../../docs/qa/m9-rejection-context-v2-scope-2026-10-22.md)
  approved b7884c940 completed0: exact helper context **dropping check in message due to
  code signing requirement** corroborates this one rejected-peer case, not full matrix or
  restoration qualification. All scopes consumed; no more query/probe. [Finite lid-open
  native baseline](../../docs/qa/m9-lid-open-native-baseline-scope-2026-10-22.md) prepared,
  12 tests PASS/template nil. Owner granted exact attended scope/accepted indefinite-policy
  risk; captured1deeec00…/foreground Terminal launcher verified without native observation/
  IPC/lease. Owner ran once: safety passed, admitted Inspect accepted/stopped/sleepObserved;
  run0/no lease, scope consumed/no retry. [Post-refusal/root read-only proposal](../../docs/qa/m9-baseline-stopped-readonly-scope-2026-10-22.md)
  prepared,13 wrapper/5 audit tests PASS. Owner granted one root-read scope, capture0e085d4b…/
  Terminal launcher verified; owner audit completed0/stderr0: final pins/files matched,
  journal absent at capture, original locks/not acquired, running PID50171. Both scopes
  consumed. [Unchanged-pin lifecycle proposal](../../docs/qa/m9-final-helper-restart-scope-2026-10-22.md)
  12 lifecycle/7 sequence tests PASS. Owner separately approved A lifecycle and B new
  conditional baseline, captured08b160ff…/8fbdacba…/sequenceb346493c… and Terminal launcher
  verified without native/root execution. Owner attempt then refused root preflight at
  sole failed thermalNominal=false (AC true/fresh11.1ms): no protected backup/bootout/
  bootstrap/IPC/lease or conditional baseline. Scopes consumed/no retry/polling; owner
  cooling/readiness then fresh safety scope required. No actual lease/manual Sleep/lid
  trial/physical credit yet. No native recorder, guardian/ownership proof,
  installed trust/binary change or new acquisition/IPC/Sleep authority.
- [x] **T202 — Sustained closed-lid sessions** with independent progress and honest display — **Review 2026-10-31:** closed as superseded by 014 G2 trial 1 (Standard backend, 5 min with the lid closed, no progress gap).
  scope.
- [x] **T203 — Failure classes:** app crash, helper crash/hang, journal corruption/permission, — **Review 2026-10-31:** closed as superseded by 014 G2 trials 3–7 and the 014 journal tests.
  AC loss, thermal, foreign override, manual Sleep, reboot with pending journal.
- [x] **T204 — Hardware rows:** target MacBook Air first; additional rows only if shipping — **Review 2026-10-31:** closed as superseded: one hardware row (Mac17,3 / 26A434) in `QualifiedSupportRows`; other Macs use the untested-configuration acceptance (014 Phase 8).
  scope expands.

## Phase 3 — G3 app integration (separate approval)

- [x] **T301 — Wire the best-effort projection behind the experimental flag** without changing — **Review 2026-10-31:** closed as superseded by 014 Phases 7–8 (Standard backend wired behind opt-in and the permit).
  the shipping backend or the `protected` state.
- [x] **T302 — Consent, banner and recovery UX** in the app. — **Review 2026-10-31:** closed as superseded by 014 T203, T302, T705, T804, T805 (install, consent, banners, conflicts).
- [x] **T303 — CLI parity** and refusal reason codes. — **Review 2026-10-31:** closed here, moved to 003 T023 (`camlid start` still refuses).
- [x] **T304 — Regression + M6:** existing suites, Debug/Release builds, UI/accessibility, — **Review 2026-10-31:** closed here, moved to M6 (007).
  CLI integration, M6 evidence pack.

## Phase 4 — G4 release gates (separate)

- [x] **T401 — M5** signing/notarisation/SMAppService install/remove/update. — **Review 2026-10-31:** closed here, moved to M5 (006); ADR 0001 excludes notarisation and `SMAppService`.
- [x] **T402 — M7** supervised real users after M6 PASS. — **Review 2026-10-31:** closed here, moved to M7 (008).

## Blocked / explicitly out of scope

Auto, Timed, battery, background/login start, completion sleep, bag/sleeve use, verified
restoration, `Protected` state, shipping-gate change, Intel/multi-display rows. Any native
action, root install, app integration or entitlement change requires a new explicit approval.
