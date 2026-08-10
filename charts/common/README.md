# common TechOps Helm Chart

## Testing

```bash
helm lint charts/common --values charts/common/test-values.yaml
helm unittest charts/common
```

## Computed values: `type: template`

Env values are literals. `type: kv` writes the string into the pod spec exactly as
written, which means a values file cannot compose one. That is fine until a value
must be repeated: an endpoint that appears in four components has to be written
four times, and nothing catches the fifth copy going stale.

`type: template` renders the value through `tpl` against the chart root, so one
key can supply many:

```yaml
global:
  queueName: elasticmq

env:
  SQS_QUEUE_URL:
    type: template
    value: "http://{{ .Values.global.queueName }}.{{ .Release.Namespace }}.svc.cluster.local:9324/000000000000/workflow-queue"
```

`.Values.global` works inside a subchart because Helm merges the parent's `global:`
map into every subchart. `.Release` is shared for the same reason. Between them an
umbrella chart can hand one value to all of its components without the operator
repeating it.

Use it only where a value must be computed. `type: kv` stays the right choice for
a plain literal, and its behaviour is unchanged - a `kv` value containing `{{` is
still written out verbatim.

### Images render the same way

`image.repository`, `image.tag` and an initContainer's `image` string accept the
same syntax, but they are only rendered when the string actually contains `{{`.
A string without it is passed through untouched, so no values file written before
0.6.0 changes behaviour. An image string that contains `{{` but is not a valid
template now fails the render rather than reaching the kubelet as a broken
reference.

## Regarding the IRSA role-arn guard

When a ServiceAccount carries an `eks.amazonaws.com/role-arn` annotation, the EKS
pod-identity webhook injects AWS credentials from it. If that annotation is ever rendered
empty or malformed the webhook injects nothing and the workload silently loses AWS access,
yet `helm upgrade` still reports success. To fail closed on that case, set
`serviceAccount.requireRoleArn: true`:

```
serviceAccount:
  create: true
  requireRoleArn: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::000000000000:role/name
```

The render then aborts with a clear message when the role-arn is empty or not a well-formed
IAM role ARN, so `helm upgrade` never applies a credential-less workload. Default is `false`,
so existing consumers are unaffected.

`serviceAccount.irsaCheck.enabled: true` additionally renders a `helm test` pod that runs
`aws sts get-caller-identity` under the ServiceAccount, validating IRSA end-to-end (run with
`helm test`).

## Regarding HTTP basic auth

This chart allows you to add basic auth to any website by simply adding the following to your `values.yaml` file:

```
httpBasicAuth:
  enabled: true
  usersList: ${USERS_LIST}
```

You can get that users list from a GH secret if you're automatically deploying from a GH workflow and have authentication for a demo/test/staging site that you don't want the public to be able to use/see.

As shown in `charts/common/values.yaml`, `usersList` is a comma-separated list of a user and a hashed password, which are separated by a colon. You can get that hashed password by using the following command:

`htpasswd -nb 'user' 'pass'`
