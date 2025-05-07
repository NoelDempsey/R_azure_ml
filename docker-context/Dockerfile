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