1. Navigate to the project
aws iam list-role-policies --role-name eks-arm64-platform-karpenter --profile eks-cluster-admin --output table

Check IAM trust relationship:
aws iam get-role --role-name eks-arm64-platform-karpenter --profile eks-cluster-admin --query 'Role.AssumeRolePolicyDocument' --output json

3. Verify AWS credentials
aws sts get-caller-identity --profile eks-cluster-admin

4. Configure Kubernetes access
aws eks update-kubeconfig --region ap-south-1 --name eks-arm64-platform --profile eks-cluster-admin

Verify connectivity:
kubectl cluster-info
kubectl get nodes

5. Validate Terraform
cd terraform

terraform init
terraform validate
terraform plan

cd ..

6. Check the Karpenter controller
kubectl get deployment karpenter -n kube-system

7. Check NodePools
kubectl get nodepools

8. Check NodeClaims
kubectl get nodeclaims

9. Check EC2NodeClass
kubectl get ec2nodeclasses

10. Verify Karpenter health
kubectl rollout status deployment/karpenter -n kube-system --timeout=120s

11. Check Karpenter Pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter

12. Check Karpenter logs
kubectl logs -n kube-system deployment/karpenter --tail=100

For live logs:
kubectl logs -n kube-system deployment/karpenter -f --tail=100

13. Verify MongoDB
kubectl get statefulsets -n mongodb
kubectl get pods -n mongodb -o wide
kubectl get pvc -n mongodb

Check MongoDB logs:
kubectl logs -n mongodb mongodb-0 --tail=50

14. Verify Argo CD
kubectl get applications -n argocd

15. Run ARM64 smoke test
Your smoke-test file is:
karpenter-arm64-scale-test.yaml

Run:
kubectl apply -f karpenter-arm64-scale-test.yaml

Verify:
kubectl get pods -n karpenter-lab -o wide

kubectl logs -n karpenter-lab karpenter-arm64-scale-test

Expected architecture output:
aarch64


16. Monitor Karpenter scaling
Terminal 1 — Nodes
kubectl get nodes -w

Terminal 2 — NodeClaims
kubectl get nodeclaims -w

Terminal 3 — Karpenter logs
kubectl logs -n kube-system \
  deployment/karpenter \
  -f --tail=100

17. Verify MongoDB disruption protection
kubectl get nodepool arm64-pool -o jsonpath='CPU Limit: {.spec.limits.cpu}{"\n"}Disruption Budget: {.spec.disruption.budgets}{"\n"}Expiration: {.spec.template.spec.expireAfter}{"\n"}'

Your previously verified values were:
CPU Limit: 4
Disruption Budget: [{"nodes":"0"}]
Expiration: Never

Check MongoDB's Pod annotation:
kubectl get pod mongodb-0 -n mongodb -o jsonpath='{.metadata.annotations.karpenter\.sh/do-not-disrupt}{"\n"}'

Expected:
true

18. Clean up the smoke test
When testing is complete:
kubectl delete -f karpenter-arm64-scale-test.yaml

#Run the argocd with port forward 
kubectl port-forward -n argocd svc/argocd-server 8080:443
