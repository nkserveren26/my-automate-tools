# 引数の定義
param (
    [string]$resourceGroupName,
    [string]$vmListFilePath
)

# エラーが発生したら処理を終了するように設定
$ErrorActionPreference = "Stop"

# Azureへのログインを実行する関数
function LoginToAzure {
    Write-Host "Azureにログインしています..."
    try {
        Connect-AzAccount > $null   # 出力結果を表示する必要はないので、結果を$nullにリダイレクト 
        Write-Host "Azureへのログインが完了しました。"
    } catch  {
        Write-Host "Azureにログインできませんでした。エラー: $_"
        exit
    }
}

# VMリストのファイルを読み込む関数
function ReadVMListFromFile {
    param (
        [string]$vmListFilePath
    )

    try {
        $vmNames = Get-Content $vmListFilePath
    } catch [System.Management.Automation.ItemNotFoundException] {
        Write-Host "ファイルが見つかりません。ファイルパス: $vmListFilePath"
        exit
    } catch {
        Write-Host "ファイルの読み込み中にエラーが発生しました。エラー: $_"
        exit
    }

    return $vmNames
}

# 処理実行
try {
    # Azureにログイン
    LoginToAzure
    
    # VMのリストをファイルから読み込む
    $vmNames = ReadVMListFromFile -vmListFilePath $vmListFilePath

    # VMの一括削除
    foreach ($vmName in $vmNames) {
        Write-Host "Deleting VM: $vmName"
        # VMのネットワークインターフェイスを取得
        $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName
        $nicId = $vm.NetworkProfile.NetworkInterfaces.Id
        $nic = Get-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name (Split-Path -Leaf $nicId)

        # NSGを解除
        if ($nic.NetworkSecurityGroup) {
            $nsgId = $nic.NetworkSecurityGroup.Id
            $nic.NetworkSecurityGroup = $null
            Set-AzNetworkInterface -NetworkInterface $nic

            # VMの削除
            Remove-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Force

            # NSGの削除
            $nsgName = (Split-Path -Leaf $nsgId)
            Write-Host "Deleting NSG: $nsgName"
            Remove-AzNetworkSecurityGroup -ResourceGroupName $resourceGroupName -Name $nsgName -Force
        } else {
            # VMの削除
            Remove-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Force
        }
        
        # OSディスクの削除
        $osDiskName = $vm.StorageProfile.OsDisk.Name
        Write-Host "Deleting OS Disk: $osDiskName"
        Remove-AzDisk -ResourceGroupName $resourceGroupName -DiskName $osDiskName -Force -Verbose

        # データディスクの削除
        foreach ($dataDisk in $vm.StorageProfile.DataDisks) {
            $dataDiskName = $dataDisk.Name
            Write-Host "Deleting Data Disk: $dataDiskName"
            Remove-AzDisk -ResourceGroupName $resourceGroupName -DiskName $dataDiskName -Force -Verbose
        }
    }

    Write-Host "All specified VMs have been deleted."
    
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
    # VM周りの処理でエラー発生時の処理
    Write-Host "VMの処理でエラーが発生したため、処理を終了します。"
    if ($_.Exception.Message.Contains("not found")) {
        # VMが存在しない場合の処理
        Write-Host "VM名 $vmName が見つかりませんでした。"
    } else {
        # VMが存在しない以外のエラーの処理
        Write-Host ("Error message is " + $_.Exception.Message)
    }
    exit
} catch {
    # 想定外のエラー発生時の処理
    Write-Host "予期せぬエラーが発生したため、処理を終了します。"
    Write-Host ("Error message is " + $_.Exception.Message)
}
