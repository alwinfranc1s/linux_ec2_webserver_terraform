#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z ${1:-} ]]; then
    printf 'Usage: bash %s AWS_REGION\n' "$0" >&2
    exit 1
fi

region=$1
row_format='%-24s %-24s %s\n'
igw_route="DestinationCidrBlock=='0.0.0.0/0' && State=='active' && starts_with(GatewayId || '', 'igw-')"

# Windows aws.exe emits CRLF; stray carriage returns overwrite terminal output.
route_tables=$(aws ec2 describe-route-tables --region "$region" --no-cli-pager \
    --query "RouteTables[?Routes[?$igw_route]].[RouteTableId,VpcId,Routes[?$igw_route] | [0].GatewayId]" \
    --output text | tr -d '\r')

if [[ -z $route_tables ]]; then
    printf 'No route tables with an active internet gateway route found in %s.\n' "$region" >&2
    exit 1
fi

printf "$row_format" 'ROUTE TABLE ID' 'VPC ID' 'INTERNET GATEWAY ID'
while read -r listed_table listed_vpc listed_igw; do
    printf "$row_format" "$listed_table" "$listed_vpc" "$listed_igw"
done <<< "$route_tables"

vpc_count=$(awk '{ print $2 }' <<< "$route_tables" | sort -u | grep -c .)
printf '\nVPCs with an active internet gateway route in %s: %s\n\n' "$region" "$vpc_count"

printf 'Enter a route table ID from the list: ' >&2
if ! read -r route_table_id; then
    route_table_id=
fi
route_table_id=${route_table_id//$'\r'/}
if [[ -z $route_table_id ]]; then
    printf '\nA route table ID is required.\n' >&2
    exit 1
fi

vpc_id=
while read -r listed_table listed_vpc _; do
    if [[ $listed_table == "$route_table_id" ]]; then
        vpc_id=$listed_vpc
        break
    fi
done <<< "$route_tables"

if [[ -z $vpc_id ]]; then
    printf 'Route table %s was not in the list for %s.\n' "$route_table_id" "$region" >&2
    exit 1
fi

cidrs=$(aws ec2 describe-vpcs --region "$region" --vpc-ids "$vpc_id" --no-cli-pager \
    --query "Vpcs[0].CidrBlockAssociationSet[?CidrBlockState.State=='associated'].CidrBlock" \
    --output text | tr -d '\r')

if [[ -z $cidrs || $cidrs == None ]]; then
    printf 'No associated IPv4 CIDRs found for %s.\n' "$vpc_id" >&2
    exit 1
fi

used_cidrs=$(aws ec2 describe-subnets --region "$region" --no-cli-pager \
    --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].CidrBlock' \
    --output text | tr -d '\r')
[[ $used_cidrs == None ]] && used_cidrs=

ip_to_int() {
    local IFS=.
    read -r a b c d <<< "$1"
    printf '%s' $(( (a << 24) | (b << 16) | (c << 8) | d ))
}

int_to_ip() {
    printf '%s.%s.%s.%s' $(( $1 >> 24 & 255 )) $(( $1 >> 16 & 255 )) $(( $1 >> 8 & 255 )) $(( $1 & 255 ))
}

# Start and end addresses of a CIDR, e.g. "167772160 167837695".
cidr_range() {
    local start size
    start=$(ip_to_int "${1%/*}")
    size=$(( 1 << (32 - ${1#*/}) ))
    start=$(( start & ~(size - 1) & 0xFFFFFFFF ))
    printf '%s %s' "$start" $(( start + size - 1 ))
}

max_suggestions=5
suggestions=()
for vpc_cidr in $cidrs; do
    prefix=$(( ${vpc_cidr#*/} > 24 ? ${vpc_cidr#*/} : 24 ))
    block_size=$(( 1 << (32 - prefix) ))
    read -r vpc_start vpc_end <<< "$(cidr_range "$vpc_cidr")"

    for (( block = vpc_start; block <= vpc_end; block += block_size )); do
        block_end=$(( block + block_size - 1 ))
        overlaps=false
        for used in $used_cidrs; do
            read -r used_start used_end <<< "$(cidr_range "$used")"
            if (( block <= used_end && used_start <= block_end )); then
                overlaps=true
                break
            fi
        done
        if [[ $overlaps == false ]]; then
            suggestions+=("$(int_to_ip "$block")/$prefix")
            (( ${#suggestions[@]} >= max_suggestions )) && break 2
        fi
    done
done

if (( ${#suggestions[@]} == 0 )); then
    printf 'No free subnet CIDRs found in %s (VPC CIDRs: %s).\n' "$vpc_id" "$cidrs" >&2
    exit 1
fi

printf '\nExisting subnet CIDRs in %s: %s\n\n' "$vpc_id" "${used_cidrs:-none}"
printf "$row_format" 'VPC ID' 'ROUTE TABLE ID' 'AVAILABLE SUBNET CIDR'
for cidr in "${suggestions[@]}"; do
    printf "$row_format" "$vpc_id" "$route_table_id" "$cidr"
done
printf '\nUse one AVAILABLE SUBNET CIDR as subnet_cidr_block.\n'
