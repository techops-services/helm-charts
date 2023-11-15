# common TechOps Helm Chart

## Testing

```bash
helm lint charts/common --values charts/common/test-values.yaml
```

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
