# r-azure-ml

In this repository we will walk through the steps needed to run and train models using R on Azure ML, including environment creation, job submission and model registration. 

For demonstration purposes we use an extract from the R data package [Palmer Penguins](https://allisonhorst.github.io/palmerpenguins/) to generate a dummy workflow.

## Contents
* [Prerequisites](#Prerequisites)
* [Typical R workflow](#Workflow)
* [Limitations](#Limitations)
* [Step 1: Adapt your R script](#step-1-adapt-your-r-script)
* [Step 2: Create an R environment](#step-2-create-an-r-environment)
* [Step 3: Run an R job](#step-3-run-an-r-job)
* [Step 4: MLFlow](#step-4-mlflow)

## Prerequisites
*   An [Azure Machine Learning workspace](https://learn.microsoft.com/en-us/azure/machine-learning/quickstart-create-resources?view=azureml-api-2).
*   [A registered data asset](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-create-data-assets?view=azureml-api-2&tabs=cli) that your job uses - can also be data stored in storage containers which can be accessed using packages such as `AzureStor`.
*   Azure [CLI and ml extension installed](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-configure-cli?view=azureml-api-2) on your compute instance.
*   [A compute cluster](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-create-attach-compute-cluster?view=azureml-api-2) to run your job.

## Workflow

A typical workflow for using R with Azure Machine Learning:
*   Develop R scripts interactively and commit project code to a repository, ideally using a package environment manager such as `renv`in order to capture project dependencies.
*   Adapt your script to run as a job in Azure Machine Learning:
    *   Remove any code that may require user interaction.
    *   Add command line input parameters to the script as necessary.
    *   If using MLFlow, include and source the `azureml_utils.R` script in the same working directory of the R script to be executed.
    *   If using MLFlow, use `crate` to package the model.
    *   If using MLFlow, include R/MLflow functions in job script to log artifacts, models, parameters, and/or tags to MLflow.
*   Submit remote asynchronous R jobs via the CLI to:
    *   Build an environment.
    *   Run your job.
*   Register your model using Azure Machine Learning studio GUI.

## Limitations
_As 07/05/2025_

| **Limitation** | **Do this instead**  |
|--|--|
| There's no R SDK | Use the Azure CLI to submit jobs.  |
| Interactive querying of workspace MLflow registry from R isn't supported. |  |
| Nested MLflow runs in R are not supported. |  |
| Parallel job step isn't supported. | Run a script in parallel `n` times using different input parameters. But you'll have to meta-program to generate `n` YAML or CLI calls to do it. |
| Programmatic model registering/recording from a running job with R isn't supported. |  |
| Zero code deployment (that is, automatic deployment) of an R MLflow model is currently not supported. | Create a custom container with `plumber` for deployment. For an example of `plumber` see [here](https://github.com/CG-Invent-UK-Analytics-AI-Learning/plumber-api-intro).|
| Scoring an R model with batch endpoints isn't supported. | |
| Azure Machine Learning online deployment yml can only use image URIs directly from the registry for the environment specification; not pre-built environments from the same Dockerfile |

## Step 1: Adapt your R script

This chapter explains how to take an existing R script and make the appropriate changes to run it as a job in Azure ML. You'll have to make most of, if not all, of the changes described here.

### Project structure
Your R project structure should contain the context in which to build an R environment, any data you want to use (depending if you're using AzureStor or not), an `azureml_utils.R` script (if using MLFlow), and job specifications in YAML files.

```
📁 r_azure_-_ml
├─ docker-context
| ├─ Dockerfile
├─ Data
| ├─ penguins.csv
├─ src
│ ├─ azureml_utils.R # Required only if using MLFLow
│ ├─ penguins.R # This is the main file to run in the job
├─ job.yml
├─ environment-job.yml
```

### Remove user interaction

Your R script must be designed to run unattended and will be executed via the `Rscript` command. Make sure you remove any interactive inputs or outputs from the script, i.e. anything requiring interactive input in the console.

### Add parsing

If your script requires any sort of input parameter (most scripts do), pass the inputs into the script via the `Rscript` call.

In your R script, parse the inputs and make the proper type conversions. Use the `optparse` package.

The following snippet shows how to:
*   initiate the parser
*   add all your inputs as options
*   parse the inputs with the appropriate data types

Add an `--output` parameter with a default value of `./outputs` so that any output of the script will be stored (e.g. `.RDS` files, plots etc).

```
# Parse yml input -------------------------------------------------------------

parser <- OptionParser()

parser <- add_option(
    parser,
    "--data_file",
    type = "character",
    action = "store",
    default = "../../data/penguins.csv"
)

parser <- add_option(
    parser, 
    "--output",
    type = "character",
    action = "store",
    default = "./outputs"
)

args <- parse_args(parser)

# Create ./outputs directory --------------------------------------------------

if (!dir.exists(args$output)) {
    dir.create(args$output)
}
```
`args` is a named list. You can use any of these parameters later in your script.

### Save job artifacts (images, data, etc.)

You can store arbitrary script outputs like data files, images, serialized R objects, etc. that are generated by the R script in Azure ML. Create an `./outputs` directory to store any generated artifacts (images, models, data, etc). Any files saved to `./outputs` will be automatically included in the run and uploaded to the experiment at the end of the run.

```
# Create and save a plot
library(ggplot2)

myplot <- ggplot(...)

ggsave(
    myplot, 
    filename = file.path(args$output,"myplot.png"))

# Save an RDS serialized object
saveRDS(myobject, file = file.path(args$output,"myobject.rds"))
```

### Script structure and example

```
# penguins.R
# Packages --------------------------------------------------------------------

library(optparse)
library(tidyverse)

# Parse yml input -------------------------------------------------------------

parser <- OptionParser()

parser <- add_option(
    parser,
    "--data_file",
    type = "character",
    action = "store",
    default = "../../data/penguins.csv"
)

parser <- add_option(
    parser, 
    "--output",
    type = "character",
    action = "store",
    default = "./outputs"
)

args <- parse_args(parser)

# Create ./outputs directory --------------------------------------------------

if (!dir.exists(args$output)) {
    dir.create(args$output)
}

# Run your R code -------------------------------------------------------------

# Read file data path provided in yml
file_name <- file.path(args$data_file)
penguins <- read_csv(file_name)

# Basic transformation
species <- penguins %>% 
  count(species)

# Save data to output
saveRDS(species, file = "outputs/species.RDS")
write_csv(species, file = "outputs/species.csv")
```
## Step 2: Create an R environment

To run R scripts in Azure ML you'll first need to either create an R environment with all the packages required - some of these will be mandatory (detailed below), or specify an R environment that's already been created when the job is submitted.

### Minimal Docker
To create a minimal R environment you'll write a Dockerfile which contains the context on how to build it. Below is an example of a minimal R environment able to run scripts on Azure ML which has a base image of `rocker/tidyverse:latest`- this has many popular R packages and their dependencies already installed.

This minimal example should be sufficient to read in data stored on Azure, as well as allow your scripts to save outputs.

```
# Dockerfile
FROM rocker/tidyverse:latest

# Install R package required
RUN R -e "install.packages('optparse', dependencies = TRUE, repos = 'https://cloud.r-project.org/')" 

# Install additional R packages to authenticate to Azure storage
RUN R -e "install.packages('AzureAuth', dependencies = TRUE, repos = 'https://cloud.r-project.org/')"
RUN R -e "install.packages('AzureStor', dependencies = TRUE, repos = 'https://cloud.r-project.org/')"
RUN R -e "install.packages('AzureRMR', dependencies = TRUE, repos = 'https://cloud.r-project.org/')"

# Any other package your project needs
# RUN R -e "install.packages('<package-to-install>', dependencies = TRUE, repos = 'https://cloud.r-project.org/')"
```
### MLFlow Docker
The minimal example does not have MLFlow capability, i.e. it doesn't allow you to log and record parameters, tags, performance etc through MLFlow. If you need this functionality, your Dockerfile would need to look like this: 

```
# Dockerfile
FROM rocker/tidyverse:latest

# Install python
RUN apt-get update -qq && \
 apt-get install -y python3-pip tcl tk libz-dev libpng-dev

RUN ln -f /usr/bin/python3 /usr/bin/python
RUN ln -f /usr/bin/pip3 /usr/bin/pip

# Install azureml-MLflow
RUN pip install azureml-MLflow --break-system-packages
RUN pip install MLflow --break-system-packages 

# Create link for python
RUN ln -f /usr/bin/python3 /usr/bin/python

# Install R packages required for logging with MLflow 
RUN R -e "install.packages('mlflow', dependencies = TRUE, repos = 'https://cloud.r-project.org/')"
RUN R -e "install.packages('carrier', dependencies = TRUE, repos = 'https://cloud.r-project.org/')"
RUN R -e "install.packages('optparse', dependencies = TRUE, repos = 'https://cloud.r-project.org/')"
RUN R -e "install.packages('tcltk2', dependencies = TRUE, repos = 'https://cloud.r-project.org/')"

# Install additional R packages to authenticate to Azure storage
RUN R -e "install.packages('AzureAuth', dependencies = TRUE, repos = 'https://cloud.r-project.org/')"
RUN R -e "install.packages('AzureStor', dependencies = TRUE, repos = 'https://cloud.r-project.org/')"
RUN R -e "install.packages('AzureRMR', dependencies = TRUE, repos = 'https://cloud.r-project.org/')"

# Any other package your project needs
# RUN R -e "install.packages('<package-to-install>', dependencies = TRUE, repos = 'https://cloud.r-project.org/')"
```
### Submit environment creation job
You can either copy these Dockerfile examples and create the job via [Azure Machine Learning studio](https://docs.azure.cn/en-us/machine-learning/how-to-manage-environments-in-studio?view=azureml-api-2#create-an-environment), or use [the Azure CLI via a YAML file](https://docs.azure.cn/en-us/machine-learning/how-to-manage-environments-v2?view=azureml-api-2#create-an-environment-from-a-docker-image). 

Assuming a project directory with the following structure, you'd submit a job via the Azure CLI by referencing the appropriate YAML specification file which itself references the Dockerfile defining the environment you want to create:

```
📁 r_azure_ml
├─ docker-context
| ├─ Dockerfile
├─ Data
| ├─ penguins.csv
├─ src
│ ├─ azureml_utils.R # Required only if using MLFLow
│ ├─ penguins.R # This is the main file (other .R files can be referenced inside if your project is more complex)
├─ job.yml
├─ environment-job.yml
```

The following example is a YAML specification file called `environment-job.yml` for an environment defined from a Docker image called `r-basic-environment`:

```
# environment-job.yml
$schema: https://azuremlschemas.azureedge.net/latest/environment.schema.json
name: r-basic-environment
build:
  path: docker-context
```
The Azure CLI command to submit the job and begin creating your environment is: 
```
az ml environment create -f <path>/<to>/environment-job.yml
```
Once the environment is created, you should see it under the `Environments` table within your Azure ML workspace, along with the context (the Dockerfile) that the environment is created from.

### Using an already available R environment
If there's an R environment already available in your workspace which meets your requirements, you might want to use it rather than created a new one. In any future YAML job specification files, you'd need only to reference the environment as the `job.yml` file does.

## Step 3: Run an R job

This sections explains how to take your adapted R script and set it up to run as an R job using the Azure ML CLI.

### Create a folder with this structure

Ensure your project directory follows a structure similar to this:

```
📁 r_azure_ml
├─ docker-context
| ├─ Dockerfile
├─ Data
| ├─ penguins.csv
├─ src
│ ├─ azureml_utils.R # Required only if using MLFLow
│ ├─ penguins.R # This is the main file (other .R files can be referenced inside if your project is more complex)
├─ job.yml
├─ environment-job.yml
```

*   The `penguins.R` file is the main R script that you adapted to run in production. Make sure you follow the steps in the [MLFlow section](#step-4-mlflow) inside this script if you want to use MLFlow. You can also reference other R scripts under the `/src` directory within your main R script if your project is more complicated.
*   The `azureml_utils.R` file is necessary to use MLFlow. Use the example `azureml_utils.R` file found in the [MLFlow section](#step-4-mlflow).

### Prepare the job YAML

Azure Machine Learning CLI has different [different YAML schemas](https://learn.microsoft.com/en-us/azure/machine-learning/reference-yaml-overview?view=azureml-api-2) for different operations. You use the [job YAML schema](https://learn.microsoft.com/en-us/azure/machine-learning/reference-yaml-job-command?view=azureml-api-2) to submit a job specified in the YAML files that are a part of this project. For example: 

```
# job.yml
$schema: https://azuremlschemas.azureedge.net/latest/commandJob.schema.json
command: >
  Rscript penguins.R
  --data_file ${{inputs.penguins_data}}
code: src
inputs:
  penguins_data:
    type: uri_file
    path: data/penguins.csv
environment: azureml:r-basic-environment@latest
compute: azureml:cpu-cluster
display_name: job-r-penguins
experiment_name: job-r-penguins
description: Output subset of Palmer Penguins dataset.
```
In some scenarios, you may not want to add in an `inputs` section in the YAML file. For instance, if you'll be connecting to and reading in data from Azure storage containers. In this case, you can just use the `AzureStor:storage_read_csv()` functions directly in the `.R` file supplied in the `command` section of the YAML file.

### Submit the job

Submitting the job is very similar to when you created an R environment: 

```
az ml job create -f <path>/<to>/job.yml
```
### Registering a model
If your R job created and outputted a model (e.g. an `.RDS` file or an MLFlow `crate` object), you can only register the model manually through the Azure ML GUI or through additional CLI commands. There's no way to automate the registration as part of the job as there is with Python.

## Step 4: MLFlow

If you plan on using MLFlow, you must source a helper script called `azureml_utils.R` from the same working directory of the R script that will be run.

The helper script is required for the running R script to be able to communicate with the MLflow server. The helper script provides a method to continuously retrieve the authentication token, since the token changes quickly in a running job.

The helper script also allows you to use the logging functions provided in the [R MLflow API](https://mlflow.org/docs/latest/R-api.html) to log models, parameters, tags and general artifacts.

```
# azureml_utils.R
# Azure ML utility to enable usage of the MLFlow R API for tracking with Azure Machine Learning (Azure ML). This utility does the following::
# 1. Understands Azure ML MLflow tracking url by extending OSS MLflow R client.
# 2. Manages Azure ML Token refresh for remote runs (runs that execute in Azure Machine Learning). It uses tcktk2 R libraray to schedule token refresh.
#    Token refresh interval can be controlled by setting the environment variable MLFLOW_AML_TOKEN_REFRESH_INTERVAL and defaults to 30 seconds.

library(mlflow)
library(httr)
library(later)
library(tcltk2)

new_mlflow_client.mlflow_azureml <- function(tracking_uri) {
  host <- paste("https", tracking_uri$path, sep = "://")
  get_host_creds <- function () {
    mlflow:::new_mlflow_host_creds(
      host = host,
      token = Sys.getenv("MLFLOW_TRACKING_TOKEN"),
      username = Sys.getenv("MLFLOW_TRACKING_USERNAME", NA),
      password = Sys.getenv("MLFLOW_TRACKING_PASSWORD", NA),
      insecure = Sys.getenv("MLFLOW_TRACKING_INSECURE", NA)
    )
  }
  cli_env <- function() {
    creds <- get_host_creds()
    res <- list(
      MLFLOW_TRACKING_USERNAME = creds$username,
      MLFLOW_TRACKING_PASSWORD = creds$password,
      MLFLOW_TRACKING_TOKEN = creds$token,
      MLFLOW_TRACKING_INSECURE = creds$insecure
    )
    res[!is.na(res)]
  }
  mlflow:::new_mlflow_client_impl(get_host_creds, cli_env, class = "mlflow_azureml_client")
}

get_auth_header <- function() {
    headers <- list()
    auth_token <- Sys.getenv("MLFLOW_TRACKING_TOKEN")
    auth_header <- paste("Bearer", auth_token, sep = " ")
    headers$Authorization <- auth_header
    headers
}

get_token <- function(host, exp_id, run_id) {
    req_headers <- do.call(httr::add_headers, get_auth_header())
    token_host <- gsub("mlflow/v1.0","history/v1.0", host)
    token_host <- gsub("azureml://","https://", token_host)
    api_url <- paste0(token_host, "/experimentids/", exp_id, "/runs/", run_id, "/token")
    GET( api_url, timeout(getOption("mlflow.rest.timeout", 30)), req_headers)
}


fetch_token_from_aml <- function() {
    message("Refreshing token")
    tracking_uri <- Sys.getenv("MLFLOW_TRACKING_URI")
    exp_id <- Sys.getenv("MLFLOW_EXPERIMENT_ID")
    run_id <- Sys.getenv("MLFLOW_RUN_ID")
    sleep_for <- 1
    time_left <- 30
    response <- get_token(tracking_uri, exp_id, run_id)
    while (response$status_code == 429 && time_left > 0) {
        time_left <- time_left - sleep_for
        warning(paste("Request returned with status code 429 (Rate limit exceeded). Retrying after ",
                    sleep_for, " seconds. Will continue to retry 429s for up to ", time_left,
                    " second.", sep = ""))
        Sys.sleep(sleep_for)
        sleep_for <- min(time_left, sleep_for * 2)
        response <- get_token(tracking_uri, exp_id)
    }

    if (response$status_code != 200){
        error_response = paste("Error fetching token will try again after sometime: ", str(response), sep = " ")
        warning(error_response)
    }

    if (response$status_code == 200){
        text <- content(response, "text", encoding = "UTF-8")
        json_resp <-jsonlite::fromJSON(text, simplifyVector = FALSE)
        json_resp$token
        Sys.setenv(MLFLOW_TRACKING_TOKEN = json_resp$token)
        message("Refreshing token done")
    }
}

clean_tracking_uri <- function() {
    tracking_uri <- httr::parse_url(Sys.getenv("MLFLOW_TRACKING_URI"))
    tracking_uri$query = ""
    tracking_uri <-httr::build_url(tracking_uri)
    Sys.setenv(MLFLOW_TRACKING_URI = tracking_uri)
}

clean_tracking_uri()
tcltk2::tclTaskSchedule(as.integer(Sys.getenv("MLFLOW_TOKEN_REFRESH_INTERVAL_SECONDS", 30))*1000, fetch_token_from_aml(), id = "fetch_token_from_aml", redo = TRUE)

# Set MLFlow related env vars
Sys.setenv(MLFLOW_BIN = system("which mlflow", intern = TRUE))
Sys.setenv(MLFLOW_PYTHON_BIN = system("which python", intern = TRUE))
```
### Crate your models
The [R MLflow API documentation](https://mlflow.org/docs/latest/models.html#r-function-crate) specifies that your R models need to be of the `crate` _model flavor_.

*   If your R script trains a model using MLFlow and you produce a model object, you'll need to `crate` it to be able to deploy it at a later time with Azure ML.
*   When using the `crate` function, use explicit namespaces when calling any package function you need.

Let's say you have a timeseries model object called `my_ts_model` created with the `fable` package. In order to make this model callable when it's deployed, create a `crate` where you'll pass in the model object and a forecasting horizon in number of periods:

```
library(carrier)
crated_model <- crate(function(x)
{
  fabletools::forecast(!!my_ts_model, h = x)
})

# Log models and parameters to MLflow
mlflow_start_run() 

mlflow_log_model(
  model = crated_model, # the crate model object
  artifact_path = "models" # a path to save the model object to
)

mlflow_log_param(<key-name>, <value>)

```


