//
//  DialogsManager.m
//  TelegramTest
//
//  Created by keepcoder on 26.10.13.
//  Copyright (c) 2013 keepcoder. All rights reserved.
//

#import "DialogsManager.h"
#import "TLPeer+Extensions.h"
#import "Telegram.h"
#import "PreviewObject.h"
#import "SenderHeader.h"
@interface DialogsManager ()
@property (nonatomic,strong) NSMutableArray *dialogs;
@property (nonatomic,assign) NSInteger maxCount;
@end

@implementation DialogsManager


-(id)initWithQueue:(ASQueue *)queue {
    if(self = [super initWithQueue:queue]) {
        [Notification addObserver:self selector:@selector(setTopMessageToDialog:) name:MESSAGE_UPDATE_TOP_MESSAGE];
        [Notification addObserver:self selector:@selector(setTopMessagesToDialogs:) name:MESSAGE_LIST_UPDATE_TOP];
        [Notification addObserver:self selector:@selector(deleteMessages:) name:MESSAGE_DELETE_EVENT];
        [Notification addObserver:self selector:@selector(updateReadList:) name:MESSAGE_READ_EVENT];
    }
    return self;
}

- (void)dealloc {
    [Notification removeObserver:self];
}



- (void)updateReadList:(NSNotification *)notify {
    NSArray *copy = [notify.userInfo objectForKey:KEY_MESSAGE_ID_LIST];
    MessagesManager *manager = [MessagesManager sharedManager];
   
    [[Storage manager] messages:^(NSArray *messages) {
        
        
        [self.queue dispatchOnQueue:^{
            NSMutableDictionary *updateDialogs = [[NSMutableDictionary alloc] init];
            int total = 0;
            for (TL_localMessage *message in messages) {
                if(message.unread && message.conversation) {
                    if(!message.n_out) {
                        if(message.conversation.unread_count != 0)
                            ++total;
                        message.conversation.unread_count--;
                        
                    }
                    
                    if(message.n_id > message.conversation.last_marked_message) {
                        message.conversation.last_marked_message = message.n_id;
                        message.conversation.last_marked_date = message.date;
                    }
                    
                    [updateDialogs setObject:message.conversation forKey:@(message.conversation.peer.peer_id)];
                }
                
            }
            
            for (TL_conversation *dialog in updateDialogs.allValues) {
                [dialog save];
                [Notification perform:DIALOG_UPDATE data:@{KEY_DIALOG:dialog}];
                [Notification perform:[Notification notificationNameByDialog:dialog action:@"unread_count"] data:@{KEY_DIALOG:dialog}];
            }
            
            manager.unread_count-=total;
            
            [[Storage manager] markMessagesAsRead:copy completeHandler:nil];
            
        }];
        
    } forIds:copy random:NO];
    
    
}


- (void)drop {
    [self.queue dispatchOnQueue:^{
        [self->list removeAllObjects];
        [self->keys removeAllObjects];
        
        [Notification perform:DIALOGS_NEED_FULL_RESORT data:@{KEY_DIALOGS:self->list}];
    }];
  
}

- (TL_conversation *)createDialogForUser:(TLUser *)user {
    TL_conversation *dialog = [TL_conversation createWithPeer:[TL_peerUser createWithUser_id:user.n_id] top_message:0 unread_count:0 last_message_date:0 notify_settings:nil last_marked_message:0 top_message_fake:0 last_marked_date:0];
    dialog.fake = YES;
    [self add:@[dialog]];
   
    return dialog;
}

- (TL_conversation *)createDialogForChat:(TLChat *)chat {
    TL_conversation *dialog = [TL_conversation createWithPeer:[TL_peerChat createWithChat_id:chat.n_id] top_message:0 unread_count:0 last_message_date:0 notify_settings:nil last_marked_message:0 top_message_fake:0 last_marked_date:0];
    dialog.fake = YES;
    [self add:@[dialog]];
    return dialog;
}

- (TL_conversation *)createDialogEncryptedChat:(TLEncryptedChat *)chat {
    TL_conversation *dialog = [TL_conversation createWithPeer:[TL_peerSecret createWithChat_id:chat.n_id] top_message:0 unread_count:0 last_message_date:0 notify_settings:nil last_marked_message:0 top_message_fake:0 last_marked_date:0];
    dialog.fake = YES;
    [self add:@[dialog]];
    return dialog;
}

- (TL_conversation *)createDialogForMessage:(TL_localMessage *)message {
    TL_conversation *dialog = [TL_conversation createWithPeer:[message peer] top_message:0 unread_count:0  last_message_date:message.date notify_settings:nil last_marked_message:message.n_id top_message_fake:0 last_marked_date:message.date];
    dialog.fake = YES;
    [self add:@[dialog]];
    return dialog;
}

- (void)deleteMessages:(NSNotification *)messages {
    
    NSArray *deleted = [messages.userInfo objectForKey:KEY_MESSAGE_ID_LIST];
    
    [self.queue dispatchOnQueue:^{
        
        [[Storage manager] deleteMessages:deleted completeHandler:nil];
        
        NSMutableDictionary *dialogstoUpdate = [[NSMutableDictionary alloc] init];
        
        for (NSNumber *msg_id in deleted) {
            TL_localMessage *message = [[MessagesManager sharedManager] find:[msg_id intValue]];
            if(message.conversation)
                [dialogstoUpdate setObject:message.conversation forKey:@(message.conversation.peer.peer_id)];
        }
        
        
        for(TL_conversation *dialog in dialogstoUpdate.allValues) {
            [self updateLastMessageForDialog:dialog];
        }
    }];
    
}

-(void)updateLastMessageForDialog:(TL_conversation *)dialog {
    
    [[Storage manager] lastMessageForPeer:dialog.peer completeHandler:^(TL_localMessage *lastMessage) {
        
        [self.queue dispatchOnQueue:^{
            
            if(lastMessage) {
                
                if(![[MessagesManager sharedManager] find:lastMessage.n_id])
                    [[MessagesManager sharedManager] TGsetMessage:lastMessage];
                
               
                dialog.top_message = lastMessage.n_id;
                dialog.last_message_date = lastMessage ? lastMessage.date : dialog.last_message_date;
                dialog.last_marked_message = lastMessage.n_id;
                dialog.last_marked_date = lastMessage.date;
                                
            } else {
                dialog.last_marked_message = dialog.top_message = dialog.last_marked_date = 0;
            }
            
            [dialog save];
            
            [Notification perform:DIALOG_UPDATE data:@{KEY_DIALOG:dialog}];
            [Notification perform:[Notification notificationNameByDialog:dialog action:@"message"] data:@{KEY_DIALOG:dialog}];
            
            NSUInteger position = [self positionForConversation:dialog];
            
            [Notification perform:DIALOG_MOVE_POSITION data:@{KEY_DIALOG:dialog, KEY_POSITION:@(position)}];

            
        }];
        
    }];

    
}

-(NSUInteger)positionForConversation:(TL_conversation *)dialog {
    [self resort];
    return [self->list indexOfObject:dialog];
}

- (void)deleteDialog:(TL_conversation *)dialog completeHandler:(dispatch_block_t)completeHandler {
    if(dialog == nil) {
        ELog(@"dialog is nil, check this");
        return;
    }
    
    dispatch_block_t newBlock = ^{
        
        dispatch_block_t block = ^{
            [[Storage manager] deleteDialog:dialog completeHandler:^{
                [self.queue dispatchOnQueue:^{
                    [self->list removeObject:dialog];
                    [self->keys removeObjectForKey:@(dialog.peer.peer_id)];
                    
                    [Notification perform:DIALOG_DELETE data:@{KEY_DIALOG:dialog}];
                    
                    MessagesManager *manager = [MessagesManager sharedManager];
                    
                    manager.unread_count-=dialog.unread_count;
                    
                    
                    
                }];
               
                if(completeHandler)
                    completeHandler();
            }];
        };
        
        if(dialog.type != DialogTypeSecretChat && dialog.type != DialogTypeBroadcast)
            [self _clearHistory:dialog offset:0 completeHandler:^{
                block();
            }];
        else {
            block();
        }
    };

    if(dialog.type == DialogTypeSecretChat) {
        [RPCRequest sendRequest:[TLAPI_messages_discardEncryption createWithChat_id:dialog.peer.chat_id] successHandler:^(RPCRequest *request, id response) {
            newBlock();
        } errorHandler:^(RPCRequest *request, RpcError *error) {
            newBlock();
        }];
        return;
    }
    
    if(dialog.type == DialogTypeBroadcast) {
        [[BroadcastManager sharedManager] remove:@[dialog.broadcast]];
        newBlock();
        return;
    }
    
    if(dialog.type == DialogTypeChat && !dialog.chat.left && dialog.chat.type == TLChatTypeNormal) {
        [MessageSender sendStatedMessage:[TLAPI_messages_deleteChatUser createWithChat_id:dialog.peer.chat_id user_id:[[UsersManager currentUser] inputUser]] successHandler:^(RPCRequest *request, id response) {
            newBlock();
        } errorHandler:^(RPCRequest *request, RpcError *error) {
            newBlock();
        }];
        return;
    }
    newBlock();
}

- (void)_clearHistory:(TL_conversation *)dialog offset:(int)offset completeHandler:(dispatch_block_t)block {
    [RPCRequest sendRequest:[TLAPI_messages_deleteHistory createWithPeer:[dialog inputPeer] offset:offset] successHandler:^(RPCRequest *request, TL_messages_affectedHistory *response) {
        if([response offset] != 0)
            [self _clearHistory:dialog offset:[response offset] completeHandler:(dispatch_block_t)block];
        else {
            if(block)
                block();
        }
    } errorHandler:^(RPCRequest *request, RpcError *error) {
        if(block)
            block();
    }];
}


-(void)clearHistory:(TL_conversation *)dialog completeHandler:(dispatch_block_t)block {
    
    dispatch_block_t blockSuccess = ^{
        dialog.top_message = 0;
        
        
        MessagesManager *manager = [MessagesManager sharedManager];
        
        manager.unread_count-=dialog.unread_count;
        
        dialog.unread_count = 0;
        
        [dialog save];
        
        [Notification perform:[Notification notificationNameByDialog:dialog action:@"message"] data:nil];
        [[Storage manager] deleteMessagesInDialog:dialog completeHandler:block];
        
    };
    
    if(dialog.type != DialogTypeSecretChat) {
        [self _clearHistory:dialog offset:0 completeHandler:^{
            blockSuccess();
        }];
    } else {
        
        FlushHistorySecretSenderItem *sender = [[FlushHistorySecretSenderItem alloc] initWithConversation:dialog];
        [sender send];
        
        blockSuccess();
    }
}

- (void)resort {
    [self->list sortUsingComparator:^NSComparisonResult(TL_conversation * obj1, TL_conversation * obj2) {
        return (obj1.last_real_message_date < obj2.last_real_message_date ? NSOrderedDescending : (obj1.last_real_message_date > obj2.last_real_message_date ? NSOrderedAscending : (obj1.top_message < obj2.top_message ? NSOrderedDescending : NSOrderedAscending)));
    }];
    
}

- (void)setTopMessageToDialog:(NSNotification *)notify {
    TL_localMessage *message = [notify.userInfo objectForKey:KEY_MESSAGE];
    
    
    BOOL update_real_date = [[notify.userInfo objectForKey:@"update_real_date"] boolValue];
    
    [self.queue dispatchOnQueue:^{
        if([message.media isKindOfClass:[TL_messageMediaPhoto class]]) {
            [[Storage manager] insertMedia:message];
            
            PreviewObject *previewObject = [[PreviewObject alloc] initWithMsdId:message.n_id media:message peer_id:message.peer_id];
            
            [Notification perform:MEDIA_RECEIVE data:@{KEY_PREVIEW_OBJECT:previewObject}];
        }
        
        [self updateTop:message needUpdate:YES update_real_date:update_real_date];
    }];
}

- (void)updateTop:(TL_localMessage *)message needUpdate:(BOOL)needUpdate update_real_date:(BOOL)update_real_date {
    
    [self.queue dispatchOnQueue:^{
        MessagesManager *manager = [MessagesManager sharedManager];
        TL_conversation *dialog = message.conversation;
        if(dialog.top_message != 0 && dialog.top_message != -1 && ((dialog.top_message > message.n_id && dialog.top_message < TGMINFAKEID)))
            return;
        
        
        if(message.unread && !message.n_out) {
            dialog.unread_count++;
            manager.unread_count++;
        }
        
        dialog.top_message = message.n_id;
        if(message.n_out) {
            dialog.last_marked_message = message.n_id;
            dialog.last_marked_date = message.date;
        }
        if(dialog.last_marked_message == 0) {
            dialog.last_marked_message = dialog.top_message;
            dialog.last_marked_date = dialog.last_message_date;
        }
        
        
        if((message.n_out|| !message.unread) && dialog.last_marked_message < message.n_id) {
            dialog.last_marked_message = message.n_id;
            dialog.last_marked_date = message.date;
        }
        
        int last_real_date = dialog.last_real_message_date;
        
        dialog.last_message_date = message.date;
        
        if(update_real_date) {
            dialog.last_real_message_date = last_real_date;
        }
        
        [dialog save];
        
        [self add:@[dialog]];
        
        
        if(needUpdate) {
            
            NSUInteger position = [self positionForConversation:dialog];
            
            [Notification perform:DIALOG_MOVE_POSITION data:@{KEY_DIALOG:dialog, KEY_POSITION:@(position)}];
            [Notification perform:[Notification notificationNameByDialog:dialog action:@"message"] data:@{KEY_DIALOG:dialog}];
        }


    }];
    
}

- (void)markAllMessagesAsRead:(TL_conversation *)dialog {
     NSArray *marked = [(MessagesManager *)[MessagesManager sharedManager] markAllInDialog:dialog];
    [Notification perform:MESSAGE_READ_EVENT data:@{KEY_MESSAGE_ID_LIST:marked}];
    [Notification perform:[Notification notificationNameByDialog:dialog action:@"unread_count"] data:@{KEY_DIALOG:dialog}];
}

- (void)insertDialog:(TL_conversation *)dialog {
    [self add:[NSArray arrayWithObject:dialog]];
    [dialog save];
}

- (void)setTopMessagesToDialogs:(NSNotification *)notify {
    NSArray *messages = [notify.userInfo objectForKey:KEY_MESSAGE_LIST];
    BOOL update_real_date = [[notify.userInfo objectForKey:@"update_real_date"] boolValue];
    NSMutableDictionary *last = [[NSMutableDictionary alloc] init];
    
    
    [self.queue dispatchOnQueue:^{
        int totalUnread = 0;
        MessagesManager *manager = [MessagesManager sharedManager];
        for (TL_localMessage *message in messages) {
            TL_conversation *dialog = message.conversation;
            
            if(dialog && (dialog.top_message > TGMINFAKEID || dialog.top_message < message.n_id)) {
                dialog.top_message = message.n_id;
                
                int last_real_date = dialog.last_real_message_date;
                
                dialog.last_message_date = message.date;
                
                if(update_real_date) {
                    dialog.last_real_message_date = last_real_date;
                }
                
                if(dialog.last_marked_message == 0) {
                    dialog.last_marked_message = dialog.top_message;
                    dialog.last_marked_date = dialog.last_message_date;
                }
                
                if((message.n_out|| !message.unread) && dialog.last_marked_message < message.n_id) {
                    dialog.last_marked_message = message.n_id;
                    dialog.last_marked_date = message.date;
                }
                
                if(!message.n_out && message.unread) {
                    dialog.unread_count++;
                    totalUnread++;
                }
                
            } else {
                [self updateTop:message needUpdate:NO update_real_date:NO];
                dialog = message.conversation;
            }
            
            if(dialog) {
                [last setObject:dialog forKey:@(dialog.peer.peer_id)];
            }
            
            if([message.media isKindOfClass:[TL_messageMediaPhoto class]]) {
                [[Storage manager] insertMedia:message];
                
                PreviewObject *previewObject = [[PreviewObject alloc] initWithMsdId:message.n_id media:message peer_id:message.peer_id];
                
                [Notification perform:MEDIA_RECEIVE data:@{KEY_PREVIEW_OBJECT:previewObject}];
            }
            
            
        }
        
        
        manager.unread_count += totalUnread;
        
        BOOL checkSort = [self resortAndCheck];
        
        [self add:last.allValues];
        
        for (TL_conversation *dialog in last.allValues) {
            [dialog save];
            
            if(checkSort) {
                [Notification perform:[Notification notificationNameByDialog:dialog action:@"message"] data:@{KEY_DIALOG:dialog}];
            }
        }
        
       // if(!checkSort) {
        [Notification perform:DIALOGS_NEED_FULL_RESORT data:@{KEY_DIALOGS:self->list}];
       // }
        
        
    }];
    
}


-(BOOL)resortAndCheck {
    NSArray *current = [self->list copy];
    
    [self resort];
    
    __block BOOL success = YES;
    
    [current enumerateObjectsUsingBlock:^(TL_conversation *obj, NSUInteger idx, BOOL *stop) {
        if(self->list[idx] != obj) {
            success = NO;
            *stop = YES;
        }
    }];
    
    return success;
}

- (void)add:(NSArray *)all {
    
    [self.queue dispatchOnQueue:^{
        [all enumerateObjectsUsingBlock:^(TL_conversation * dialog, NSUInteger idx, BOOL *stop) {
            TL_conversation *current = [keys objectForKey:@(dialog.peer.peer_id)];
            if(current) {
                current.unread_count = dialog.unread_count;
                current.top_message = dialog.top_message;
                current.last_message_date = dialog.last_message_date;
                current.notify_settings = dialog.notify_settings;
                current.fake = dialog.fake;
                current.last_marked_message = dialog.last_marked_message;
                current.top_message_fake = dialog.top_message_fake;
                current.last_marked_date = dialog.last_marked_date;
                current.last_real_message_date = dialog.last_real_message_date;
                current.dstate = dialog.dstate;
            } else {
                [self->list addObject:dialog];
                [self->keys setObject:dialog forKey:@(dialog.peer.peer_id)];
                current = dialog;
            }
            
            if(!current.notify_settings) {
                current.notify_settings = [TL_peerNotifySettingsEmpty create];
                [current save];
            }
            
            [self resort];
            
        }];
    }];
}

- (TL_conversation *)findByUserId:(int)user_id {
    
    __block TL_conversation *dialog;
    
    [self.queue dispatchOnQueue:^{
        dialog = [self->keys objectForKey:@(user_id)];
    } synchronous:YES];
    
    return dialog;
}

-(id)find:(NSInteger)_id {
    __block TL_conversation *dialog;
    
    [self.queue dispatchOnQueue:^{
        dialog = [self->keys objectForKey:@(_id)];
    } synchronous:YES];
    
    return dialog;
}

- (TL_conversation *)findByChatId:(int)chat_id {
    
    __block TL_conversation *dialog;
    
    [self.queue dispatchOnQueue:^{
        dialog = [self->keys objectForKey:@(-ABS(chat_id))];
    } synchronous:YES];
    
    return dialog;
}

- (TL_conversation *)findBySecretId:(int)chat_id {
    __block TL_conversation *dialog;
    
    [self.queue dispatchOnQueue:^{
        dialog = [self->keys objectForKey:@(chat_id)];
    } synchronous:YES];
    
    return dialog;
}



+(id)sharedManager {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        instance = [[[self class] alloc] initWithQueue:[ASQueue globalQueue]];
    });
    return instance;
}


@end
