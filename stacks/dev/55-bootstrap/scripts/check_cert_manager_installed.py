#!/usr/bin/env python3
"""Detect whether cert-manager is already installed in the target cluster.

Used by Terraform 'external' data source to skip cert-manager Helm installation
when a release already exists (e.g., installed manually, via another stack, or
via ArgoCD). This avoids Helm error: "cannot re-use a name that is still in use".

Input (JSON):
  - kubeconfig_path: kubeconfig file path
  - kubeconfig_context: optional kubeconfig context
  - namespace: namespace to check (default: cert-manager)

Output (JSON):
  - installed: "true" | "false"
  - details: short reason string
"""

import json
import os
import subprocess
import sys
from typing import Optional


def run_kubectl(args, kubeconfig_path: str, context: Optional[str]) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env["KUBECONFIG"] = os.path.expanduser(kubeconfig_path)

    cmd = ["kubectl"]
    if context:
        cmd += ["--context", context]
    cmd += args

    return subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )


def main() -> None:
    query = json.load(sys.stdin)

    kubeconfig_path = query.get("kubeconfig_path") or "~/.kube/config"
    kubeconfig_context = query.get("kubeconfig_context") or ""
    namespace = query.get("namespace") or "cert-manager"

    installed = False
    details = "not-found"

    try:
        # Primary signal: deployment exists
        r = run_kubectl(["-n", namespace, "get", "deploy", "cert-manager"], kubeconfig_path, kubeconfig_context or None)
        if r.returncode == 0:
            installed = True
            details = "deployment"
        else:
            # Secondary signal: core CRD exists
            r2 = run_kubectl(["get", "crd", "certificates.cert-manager.io"], kubeconfig_path, kubeconfig_context or None)
            if r2.returncode == 0:
                installed = True
                details = "crd"

    except FileNotFoundError:
        installed = False
        details = "kubectl-not-found"

    print(json.dumps({"installed": "true" if installed else "false", "details": details}))


if __name__ == "__main__":
    main()
