function Get-BalancedVirtualDiskSize {
    <#
    .Synopsis
       Figure out how big to make Virtual Disks in a Storage Spaces Direct Cluster.
    .DESCRIPTION
       Given the number of nodes, disks per node, and size of disks, the function will tell you how large to make a virtual disk so you can have 2 per node and still maintain appropriate reserve capacity.
    .EXAMPLE
       Get-BalancedVirtualDiskSize -nodecount 5 -capacityDiskSizeInBytes 5.46TB -capacityDisksPerNode 12 -Media Hybrid -Layout Parity
    .EXAMPLE
       Get-BalancedVirtualDiskSize -nodecount 8 -capacityDiskSizeInBytes 5.46TB -capacityDisksPerNode 8 -Media AllFlash -CSVPerNode 4 -clusterCapacityUsedAlreadySizeInBytes 2TB
    .NOTES
       Not doing calculations for 2 nodes, I have no idea how that even works... 
       MRV not implemented yet.
    .OUTPUTS
       Size of recommended virtual disk in Bytes, it is recommended to take the value and divide by 1TB to make it human readable
    #>
    [cmdletbinding()]
    [outputtype([double])]
    param (
        # Number of servers in the S2D cluster
        [parameter(mandatory=$true)][validaterange(3,16)][int]$nodeCount,
        # Size of the disks of the capacity tier in Bytes
        [parameter(mandatory=$true)][double]$capacityDiskSizeInBytes,
        # Number of disks of the capacity tier per server
        [parameter(mandatory=$true)][int]$capacityDisksPerNode,
        # AllFlash - Cluster is all NVME and or SSD, Hybrid - Cluster contains HDDs
        [parameter(mandatory=$true)][validateset("Hybrid","AllFlash")][string]$Media,
        # If you have already allocated some storage, this is reported in the cluster manager.
        [parameter()][double]$clusterCapacityUsedAlreadySizeInBytes=0,
        # The number of virtual disks per node, recommended amount, and default is 2
        [parameter()][int]$CSVPerNode=2,
        # 3 Way Mirror or Dual Parity, default is Mirror
        [parameter()][validateset("Mirror","Parity")][string]$Layout="Mirror",
        # Percentage of the Performance Tier that Virtual disks will be composed of, not yet implemented.
        [parameter()][single]$PercentPerformance=0.0 #mrv not implemented yet
    )

    #reserve capacity of 1 drive per capacity media type per node up to 4 nodes in S2D Docs
    if ($nodeCount -ge 4) {
        $reserveDiskCount = 4
    } else {
        $reserveDiskCount = $nodeCount
    }
    $ClusterDiskCount = ($nodeCount * $capacityDisksPerNode) - $reserveDiskCount
    $UsableRaw = ($ClusterDiskCount * $capacityDiskSizeInBytes) - $clusterCapacityUsedAlreadySizeInBytes
    $UsableRawPerNode = $UsableRaw / $nodeCount
    #best practice is 2 CSVs per node per S2D docs
    $UsableRawPerCSV = $UsableRawPerNode / $CSVPerNode
    $Efficiency = 0.0
    if ("Mirror" -eq $Layout) {
        $Efficiency = 1 / 3
    } elseif ("Parity" -eq $Layout) {
        if ("Hybrid" -eq $Media) {
            switch ($nodeCount) {
                {4..6 -contains $_} {
                    #RS2+2
                    $D=2;$P=1;$Q=1
                }
                {7..11 -contains $_} {
                    #RS4+2
                    $D=4;$P=1;$Q=1
                }
                {12..16 -contains $_} {
                    #LCR(8,2,1)
                    $D=8;$P=2;$Q=1
                }
            }
        } 
        elseif ("AllFlash" -eq $Media) {
            Switch ($nodeCount) {
                {4..6 -contains $_} {
                    #RS2+2
                    $D=2;$P=1;$Q=1
                }
                {7..8 -contains $_} {
                    #RS4+2
                    $D=4;$P=1;$Q=1
                }
                {9..15 -contains $_} {
                    #RS6+2
                    $D=6;$P=1;$Q=1
                }
                {16 -contains $_} {
                    #LRC(12,2,1)
                    $D=12;$P=2;$Q=1
                }
            }
        } 
        else {
            #Cant handle 3 media systems yet
            Write-Error "cant process 3 media systems yet"
            exit
        }
        $Efficiency = $D/($P+$Q+$D)
    } else {
        #Cant handle MRV yet.
        Write-Error "cant process 3 media systems yet"
        exit
    }
    $CSVSizeInBytes = $UsableRawPerCSV * $Efficiency
    return $CSVSizeInBytes
}

