#!/bin/bash
TELEGRAM_GROUP_ID=''
# telegram_functions

send_to_telegram() {
    local TOKEN=""
    local CHAT_ID="$1"
    local MESSAGE="$2"

    # gui tin nhan bang curl
    curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="${MESSAGE}"
}
HOST_IP=$(hostname -i)
percent_partion_root=$(df -h / | awk 'NR==2 {print $5}' | tr -d "%" | awk '{print int($1)}')
DIR=/home/minio/backup-metfone/metfone/metfone-minio/172.16.106.57
tmp_dir=/tmp/backup-minio
# kiểm tra dung lượng / xem còn trong bao nhiều %
if [ $percent_partion_root -lt 80 ]; then
    # dung lượng < 80%, không làm gì, thực hiện ghi log vào file log
    echo  "partion / in server minio IP $HOST_IP < 80%" >> /var/log/checkDiskandBackupMinio.log
else
    # Dung lượng >= 80% tiến hành xoá các file tmp backup đi
    M_TIME_DELETE=2 #Xoá các bản tmp backup > 2 ngày trước.
    while [ $percent_partion_root -eq 80 -o $percent_partion_root -gt 80 ] ; do
        if [ $M_TIME_DELETE -gt 0 ]; then 
            # thực hiện kiểm tra file backup trên Nas đã tồn tại không, nếu tồn tại thì tiến hành delete các file tmp của ngày đó.
            date_check_file_delete=$(date -d "$(date) -$M_TIME_DELETE days" +%F)
            file_check_before_delete=$(find $DIR/$date_check_file_delete -type f )
            if [ -z $file_check_before_delete ]; then
                # file backup không tồn tại trên NAS, thông báo lên telegram, - 1 ngày vào biến M_TINE_DELETE và tiếp tục vòng lặp
                send_to_telegram "$TELEGRAM_GROUP_ID" "Task auto clear Disk Metfone $HOST_IP \
                The backup file for $date_check_file_delete does not exist. The program will check the backup file for the next day."
                M_TIME_DELETE=$(( M_TIME_DELETE - 1 ))
                continue
            else
                # File backup tồn tại, tiến hành delete file tmp của ngày backup đó
                #kiểm tra xem thư mục tm đó có phải là thư mục rỗng hay không, Nếu là thư mục rỗng tiến hành xoá thư mục đó giảm biến M_TIME_DELETE đi 1 và tiếp tục vòng lặp
                if [ -d "$tmp_dir/$date_check_file_delete" ]; then
                     # thư mục tmp backup tồn tại
                     if [ -z "$(ls -A "$tmp_dir/$date_check_file_delete")" ] ; then
                        # thư mục rỗng, tiến hành delete thư mục rỗng, giảm biến M_TIME_delete đi 1, tiếp tục vòng lặp
                        find $tmp_dir -type d -mtime +$M_TIME_DELETE -exec rm -rf {} \;
                        M_TIME_DELETE=$(( M_TIME_DELETE - 1 ))
                        continue
                     else
                        # thực mục không rỗng, tiến hành delete các file, gửi thông báo đến telegram và kiểm tra lại dung lượng /
                        tmp_size=$(du -sh $tmp_dir/$date_check_file_delete | awk '{print $1}')
                        find $tmp_dir -type d -mtime +$M_TIME_DELETE -exec rm -rf {} \;
                        send_to_telegram "$TELEGRAM_GROUP_ID" "Task auto clear Disk Metfone $HOST_IP \
                        Task cleared data from $tmp_dir/$date_check_file_delete directory. size reduced by $tmp_size"
                        sleep 60s
                        percent_partion_root=$(df -h / | awk 'NR==2 {print $5}' | tr -d "%" | awk '{print int($1)}')                        
                     fi
                else
                     # thư mục tmp backup không tồn tại, tiến hành giảm biến M_TIME_DELETE và tiếp tục vòng lặp
                    send_to_telegram "$TELEGRAM_GROUP_ID" "Task auto clear Disk Metfone $HOST_IP \
                    The tmp backup file for $date_check_file_delete does not exist. The program will check the backup file for the next day."
                    M_TIME_DELETE=$(( M_TIME_DELETE - 1 ))
                    continue
                fi
                
            fi
            
        elif [ $M_TIME_DELETE -eq 0 ] ; then
            ## thực hiện delete file tmp chính ngày hôm nay
            if [ -z "$(find $DIR/$(date +%F) -type f )" ] ; then
                 # file backup khong ton tai
                M_TIME_DELETE=$(( M_TIME_DELETE - 1 ))
                continue
            else
                 # File backup ton tai
                 # check dung lượng file backup trên NAS vs dung luong tmp hôm nay
                 file_size_backup_on_nas=$( find $DIR/$(date +%F) -type f -exec du -s {} \;)
                 file_size_backup_on_tmp=$(du -s $tmp_dir/$(date +%F) | awk '{print $1}' )
                 percent=$(echo "scale=2; ( $file_size_backup_on_nas / $file_size_backup_on_tmp ) * 100" | bc )
                 # Nếu file trên NAS lớn hơn file tmp thì xoá, Nếu file tmp lớn hơn trên Nas thì không xoá và kiểm tra lại
                 if [ $percent -lt 90 ]; then
                     # không xoá, thông báo lên telegram và thoát vòng lặp
                     send_to_telegram "$TELEGRAM_GROUP_ID" "Task auto clear Disk Metfone $HOST_IP \
                     The file backup on NAS < file tmp  at $tmp_dir/$(date +%F). Task auto clear disk wasn't excuted. Please manual check"
                     break
                 else
                     # Xoá và thông báo lên telegram
                    # thực mục không rỗng, tiến hành delete các file, gửi thông báo đến telegram và kiểm tra lại dung lượng /
                    tmp_size=$(du -sh $tmp_dir/$(date +%F) | awk '{print $1}')
                    find $tmp_dir -type d -mtime +$M_TIME_DELETE -exec rm -rf {} \;
                    send_to_telegram "$TELEGRAM_GROUP_ID" "Task auto clear Disk Metfone $HOST_IP \
                    Task cleared data from $tmp_dir/$(date +%F) directory. size reduced by $tmp_size"
                    sleep 60s
                    percent_partion_root=$(df -h / | awk 'NR==2 {print $5}' | tr -d "%" | awk '{print int($1)}')
                 fi
                 
            fi
            
        else
            # Thực hiện backup minio 
            /root/minio/backup-minio.sh
        fi
    done
fi
