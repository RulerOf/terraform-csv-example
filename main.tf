# Creating terraform resources from a CSV file with an external data source
data "external" "csv_file" {
  program = ["jq", "--slurp", "--raw-input", "--raw-output", "split(\"\n\") | .[1:] | map(select(length > 0) | split(\",\")) | map({\"name\": .[0], \"value\": .[1], \"description\": .[2], \"tag\": .[3]}) | {\"names\": map(.name) | join(\",\"), \"values\": map(.value) | join(\",\"), \"description\": map(.description) | join(\",\"), \"tag\": map(.tag) | join(\",\")}", "${path.module}/sample.csv"]
}


resource "null_resource" "csv_external_data_source_method" {
  count = "${length(split(",", data.external.csv_file.result.names))}"
  triggers = {
    name = "${element(split(",", data.external.csv_file.result.names), count.index)}"
    value = "${element(split(",", data.external.csv_file.result.values), count.index)}"
    description = "${element(split(",", data.external.csv_file.result.description), count.index)}"
    tag = "${element(split(",", data.external.csv_file.result.tag), count.index)}"
  }
}

# Creating terraform resources from a CSV file using interpolation
data "null_data_source" "csv_file" {
  inputs = {
    file_data = "${chomp(file("${path.module}/sample.csv"))}"
  }
}

resource "null_resource" "csv_interpolation_method" {
  count = "${length(slice(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")), 1, length(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")))))}"

  triggers = {
    name = "${element(split(",", element(slice(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")), 1, length(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")))), count.index)), 0)}"
    value = "${element(split(",", element(slice(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")), 1, length(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")))), count.index)), 1)}"
    description = "${element(split(",", element(slice(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")), 1, length(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")))), count.index)), 2)}"
    tag = "${element(split(",", element(slice(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")), 1, length(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")))), count.index)), 3)}"
  }
}
