# Kubernetes Deployment and Service Example

This guide walks you through deploying a web application in a Kubernetes cluster using `kind`. You'll create a Deployment and expose it via a Service to make the application accessible externally.

## Step 1: Deploy the Application

1. **Create a Deployment YAML file (`app-deployment.yaml`):**

```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: my-app
   spec:
       replicas: 1
       selector:
         matchLabels:
           app: my-app
       template:
         metadata:
           labels:
             app: my-app
         spec:
           containers:
           - name: my-app
             image: <your-image>  # Replace with your actual Docker image
             ports:
             - containerPort: 80
```
**Apply the deployment:**

**Run the following command to deploy your app:**
```sh
kubectl apply -f app-deployment.yaml
```
## Step 2: Expose the application

```yml
yaml
Copy code
apiVersion: v1
kind: Service
metadata:
  name: my-app-service
spec:
  selector:
    app: my-app
  ports:
    - protocol: TCP
      port: 80  # Port the service will listen on
      targetPort: 80  # Port your application listens on
      nodePort: 30001  # Port on the host machine to expose
  type: NodePort
```
**Apply the service:**

**Run the following command to create the service:**

```sh
kubectl apply -f app-service.yaml
```

## Step 3: Access the application externally
Since kind runs in Docker, the NodePort service is exposed on your local machine's IP address. To access your app from the internet, follow these steps:

Find the IP of the kind cluster:
```sh
docker inspect kind-control-plane | grep "IPAddress"
```

This will give you the internal IP address of the kind node. However, to access it externally, you may need to configure port forwarding or use a public IP.

**Port Forwarding (if running on localhost):**

If you are running cluster locally, you can use port forwarding to expose the service to your local machine:

```sh
kubectl port-forward service/my-app-service 8080:80
```
Then, open your browser and go to http://localhost:8080 to access the application.