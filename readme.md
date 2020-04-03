# Update 2020-04-02

Do not use this. [Terraform 0.12 introduced `csvdecode()`](https://www.terraform.io/docs/configuration/functions/csvdecode.html), which you should use instead.

This technique is unnecessary and was never really recommended. It was mostly an advanced walkthrough of just how far you could push Terraform's interpolation functions to make up for missing features.

The original text follows.

--------

This originally spawned from [a reddit thread](https://www.reddit.com/r/Terraform/comments/8h7k9v/how_to_create_large_number_of_resoucres_in/) asking how to create resources from a CSV file.

This repo contains a slightly edited version of my answer, along with the code I used just for reference.

# How do I create terraform resources from a CSV file?

There's no simple answer here. I will warn you that **the solution is very obtuse and I do not recommend using it.**

I took a sample CSV and realized that to get it into terraform, the only two routes are to either convert it to a single JSON object and then read it in with the [external data source](https://www.terraform.io/docs/providers/external/data_source.html),  or to build a CSV parser out of terraform interpolation syntax. We'll try both.

<!-- TOC depthFrom:1 depthTo:6 withLinks:1 updateOnSave:1 orderedList:0 -->

- [How do I create terraform resources from a CSV file?](#how-do-i-create-terraform-resources-from-a-csv-file)
	- [Using an External Data Source](#using-an-external-data-source)
	- [Using raw Terraform Interpolation](#using-raw-terraform-interpolation)
	- [Explanation](#explanation)
		- [How the count works](#how-the-count-works)
		- [How the values work](#how-the-values-work)
- [Conclusion](#conclusion)

<!-- /TOC -->

## Using an External Data Source

First, let's look at using the External Data source. This one front-loads the insanity by [using JQ to format the data](https://gist.github.com/RulerOf/0c95c1f6344479f9c064079fc6070b85) for consumption by the external provider:

```hcl
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
```

That single resource gives us a `terraform plan` output that will count out to the end of the CSV and generate a resource for each CSV entry:

```
+ null_resource.csv_external_data_source_method[0]
    id:                   <computed>
    triggers.%:           "4"
    triggers.description: "geolocation"
    triggers.name:        "China-1.0.1.0-24"
    triggers.tag:         "maxmind"
    triggers.value:       "1.0.1.0/22"

+ null_resource.csv_external_data_source_method[1]
    id:                   <computed>
    triggers.%:           "4"
    triggers.description: "geolocation"
    triggers.name:        "China-1.0.2.0-24"
    triggers.tag:         "maxmind"
    triggers.value:       "1.0.2.0/23"
```

You'll obviously need to have jq installed.

It's worth mentioning that this can probably be made less crazy by using a script to parse the data and feed something a little more dynamic to JQ, but JQ and I don't have quite that kind of relationship ;)

## Using raw Terraform Interpolation

This strategy has us performing lots of repetitive interpolation thanks to a few limitations in the [null data source](https://www.terraform.io/docs/providers/null/data_source.html). In this example, the data source is pretty short, but the resource where we use the data is incomprehensibly long, with each key in the resource using no fewer than eight interpolation functions:

```hcl
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
```

Nonetheless, we end up with identical `terraform plan` output:

```
+ null_resource.csv_interpolation_method[0]
    id:                   <computed>
    triggers.%:           "4"
    triggers.description: "geolocation"
    triggers.name:        "China-1.0.1.0-24"
    triggers.tag:         "maxmind"
    triggers.value:       "1.0.1.0/22"

+ null_resource.csv_interpolation_method[1]
    id:                   <computed>
    triggers.%:           "4"
    triggers.description: "geolocation"
    triggers.name:        "China-1.0.2.0-24"
    triggers.tag:         "maxmind"
    triggers.value:       "1.0.2.0/23"
```

## Explanation

Of the two, I actually consider the interpolation technique to be the better choice. It's pure terraform and somehow less obtuse. Somehow. Now, let's walk through some of the interpolation:

### How the count works

```hcl
split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data"))
```

* This gives us a list where each element of the list is a line of our CSV file.

```hcl
slice(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")), 1, length(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data"))))
```

* We need to remove the CSV header, so we'll `slice()` it starting from line 1 and going to the `length()` of the list itself.

```hcl
count = "${length(slice(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")), 1, length(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")))))}"
```

* The `length()` of the now header-free list is how many times we want to `count` the resource we're creating from the CSV data.

### How the values work

```hcl
element(slice(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")), 1, length(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")))), count.index)
```

* We take our primitive from above and use `element()` to choose the item from the list that matches the current `count.index`. At this point, it's raw CSV like `China-1.0.1.0-24,1.0.1.0/22,geolocation,maxmind`

```hcl
split(",", element(slice(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")), 1, length(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")))), count.index))
```

* We take the CSV and `split()` it on every comma to get a list where each element is a column of the CSV line

```hcl
name = "${element(split(",", element(slice(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")), 1, length(split("\n", lookup(data.null_data_source.csv_file.outputs, "file_data")))), count.index)), 0)}"
```

* Finally, we use `element()` to extract the contents of a specific column as the value for each of the keys in our resource.


# Conclusion

You can do it, but the lack of any real answer elsewhere on the internet... turns out it's for a reason. There's special code in each of these techniques to ensure that the first line of the CSV isn't processed, so your CSV _must_ have a header just like the example one does if you see fit to use this.

I'm only really writing this up here because it's a topic that I couldn't find really anywhere on the Internet, and since it's _possible_, I decided I had to figure out just how it would have to work. Perhaps solving this here could lead to a better implementation by someone else, but I'm not really sure about that. Terraform could probably stand to have some proper CSV/JSON support instead. Also, this technically doesn't even follow [the spec](https://tools.ietf.org/html/rfc4180) because it doesn't handle properly-escaped commas which CAN exist in a CSV file.

Cheers.
