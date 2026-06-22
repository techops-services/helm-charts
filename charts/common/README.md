# common TechOps Helm Chart

## Testing

```bash
helm lint charts/common --values charts/common/test-values.yaml
```

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
