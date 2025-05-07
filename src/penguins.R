
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